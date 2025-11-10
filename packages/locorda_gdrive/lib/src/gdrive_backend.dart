import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_gdrive/src/auth/gdrive_auth_provider.dart';
import 'package:locorda_gdrive/src/gdrive_type_index_manager.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('GDriveBackend');
final _clientLog = Logger('GDriveClient');

/// Google Drive API client for RDF document storage.
///
/// Provides low-level Google Drive operations with OAuth2 authentication,
/// ETag-based concurrency control, and automatic token refresh on 401 errors.
class GDriveClient {
  final RdfCore _rdfCore;
  final drive.DriveApi _driveApi;

  GDriveClient._({
    required RdfCore rdfCore,
    required drive.DriveApi driveApi,
  })  : _rdfCore = rdfCore,
        _driveApi = driveApi;

  factory GDriveClient(
      {required GDriveAuthProvider authProvider, RdfCore? rdfCore}) {
    final client = _GoogleAuthClient(authProvider);
    final driveApi = drive.DriveApi(client);
    return GDriveClient._(
      rdfCore: rdfCore ??
          RdfCore.withStandardCodecs(iriTermFactory: IriTerm.validated),
      driveApi: driveApi,
    );
  }

  /// Get or create a folder in Google Drive.
  ///
  /// Searches for existing folder by name in parent (or root), creates if not found.
  /// Returns the folder ID (suitable for use as parentId in other operations).
  ///
  /// Parameters:
  /// - [folderName]: Name of folder to find or create
  /// - [parentId]: Parent folder ID, or null for root ('root' is Drive's root folder ID)
  ///
  /// Throws [GDriveClientException] if user not authenticated or API error occurs.
  Future<String> getOrCreateFolder({
    required String folderName,
    String? parentId,
  }) async {
    final parent = parentId ?? 'root';

    try {
      _clientLog.fine('Searching for folder "$folderName" in parent=$parent');

      // Search for existing folder
      // Query: name matches AND mimeType is folder AND parent is specified
      final escapedName = GDriveClient._escapeQueryValue(folderName);
      final query =
          "name='$escapedName' and mimeType='application/vnd.google-apps.folder' and '$parent' in parents and trashed=false";

      final fileList = await _driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final folderId = fileList.files!.first.id!;
        _clientLog.fine('Found existing folder: $folderId');
        return folderId;
      }

      _clientLog.fine('Folder not found, creating new folder');

      // Create new folder
      final folderMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      // Only set parents if not root (omitting parents creates in root)
      if (parentId != null) {
        folderMetadata.parents = [parent];
      }

      final createdFolder = await _driveApi.files.create(
        folderMetadata,
        $fields: 'id',
      );

      final folderId = createdFolder.id!;
      _clientLog.info('Created folder "$folderName" with ID: $folderId');
      return folderId;
    } catch (e, stackTrace) {
      _clientLog.severe(
          'Failed to get or create folder "$folderName"', e, stackTrace);
      throw GDriveClientException(
          'Failed to get or create folder "$folderName": $e');
    }
  }

  Future<({String fileId, String etag})> createFile(
      String filename, RdfGraph graph,
      {required String folderId,
      bool fileNameMayBeRelativePath = false}) async {
    throw UnimplementedError();
  }

  /// Find a file in Google Drive by name and parent folder.
  ///
  /// Returns the file ID if found, null otherwise.
  ///
  /// **Path Handling:**
  /// - If [fileNameMayBeRelativePath] is false: Searches for exact filename in [parentId]
  ///   - `fileName = "data.ttl"` → searches in parentId
  ///   - `fileName = "my/file.ttl"` → searches for file literally named "my/file.ttl"
  ///
  /// - If [fileNameMayBeRelativePath] is true: Interprets slashes as folder hierarchy
  ///   - `fileName = "data.ttl"` → searches in parentId
  ///   - `fileName = "subfolder/data.ttl"` → searches in parentId/subfolder/
  ///   - Creates missing folders automatically
  ///
  /// Parameters:
  /// - [fileName]: File name (with optional path if [fileNameMayBeRelativePath] is true)
  /// - [parentId]: Parent folder ID to search in
  /// - [fileNameMayBeRelativePath]: Whether to interpret slashes as folder separators
  ///
  /// Returns file ID if found, null if not found.
  Future<String?> findFile({
    required String fileName,
    required String parentId,
    bool fileNameMayBeRelativePath = false,
  }) async {
    try {
      // Handle relative paths by traversing folder hierarchy
      if (fileNameMayBeRelativePath && fileName.contains('/')) {
        final parts = fileName.split('/');
        final folderPath = parts.sublist(0, parts.length - 1);
        final actualFileName = parts.last;

        // Navigate/create folder hierarchy
        String currentParentId = parentId;
        for (final folderName in folderPath) {
          currentParentId = await getOrCreateFolder(
              folderName: folderName, parentId: currentParentId);
        }

        // Search for file in final folder
        return await _findFileInFolder(
            fileName: actualFileName, parentId: currentParentId);
      }

      // Direct search in parent folder
      return await _findFileInFolder(fileName: fileName, parentId: parentId);
    } catch (e, stackTrace) {
      _clientLog.severe('Failed to find file "$fileName"', e, stackTrace);
      throw GDriveClientException('Failed to find file "$fileName": $e');
    }
  }

  /// Internal helper: Search for file by exact name in specific folder.
  Future<String?> _findFileInFolder({
    required String fileName,
    required String parentId,
  }) async {
    _clientLog.fine('Searching for file "$fileName" in folder=$parentId');

    final escapedName = _escapeQueryValue(fileName);
    final query =
        "name='$escapedName' and '$parentId' in parents and trashed=false";

    final fileList = await _driveApi.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      final fileId = fileList.files!.first.id!;
      _clientLog.fine('Found file: $fileId');
      return fileId;
    }

    _clientLog.fine('File not found');
    return null;
  }

  Future<({RdfGraph? graph, String? etag, bool notModified})> download(
      String fileId,
      {String? ifNoneMatch}) async {
    throw UnimplementedError();
  }

  Future<RemoteUploadResult> upload(String fileId, RdfGraph updatedGraph,
      {required String ifMatch}) async {
    throw UnimplementedError();
  }

  /// Escape special characters in Drive API query values.
  ///
  /// Google Drive API requires escaping:
  /// - Single quote (') → \'
  /// - Backslash (\) → \\
  ///
  /// See: https://developers.google.com/drive/api/guides/search-files
  static String _escapeQueryValue(String value) {
    return value
        .replaceAll('\\', '\\\\') // Backslash must be escaped first!
        .replaceAll("'", "\\'"); // Then escape single quotes
  }
}

/// HTTP client for googleapis library that adds Bearer token authentication.
///
/// The googleapis package requires an authenticated http.Client.
/// This minimal implementation adds the OAuth2 access token to all requests.
class _GoogleAuthClient extends http.BaseClient {
  final GDriveAuthProvider _authProvider;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._authProvider);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final _accessToken = _authProvider.getAccessToken();
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

class GDriveClientException implements Exception {
  final String message;
  GDriveClientException(this.message);
}

class GDriveSyncStorage implements RemoteSyncStorage {
  final GDriveClient _client;

  final TypeIndexMappings _typeIndexMappings;
  final ResourceLocator _resourceLocator;

  GDriveSyncStorage({
    required GDriveClient client,
    required TypeIndexMappings typeIndexMappings,
    required ResourceLocator resourceLocator,
  })  : _client = client,
        _typeIndexMappings = typeIndexMappings,
        _resourceLocator = resourceLocator;

  @override
  Future<RemoteDownloadResult> download(IriTerm documentIri,
      {String? ifNoneMatch}) async {
    final docIri = _resourceLocator.fromIri(documentIri);
    final folderId = _typeIndexMappings.getFolderId(docIri.typeIri);
    final filePath = docIri.id;
    final fileId = await _client.findFile(
        parentId: folderId,
        fileName: filePath,
        fileNameMayBeRelativePath: true);
    if (fileId == null) {
      return RemoteDownloadResult(
        graph: null,
        etag: null,
        notModified: false,
      );
    }
    final result = await _client.download(fileId, ifNoneMatch: ifNoneMatch);
    if (result.notModified) {
      return RemoteDownloadResult.notModified(etag: result.etag);
    }
    if (result.graph == null) {
      return RemoteDownloadResult(
        graph: null,
        etag: result.etag,
        notModified: false,
      );
    }
    return RemoteDownloadResult(
      graph: result.graph!,
      etag: result.etag,
      notModified: false,
    );
  }

  @override
  Future<RemoteUploadResult> upload(IriTerm documentIri, RdfGraph graph,
      {String? ifMatch}) async {
    final docIri = _resourceLocator.fromIri(documentIri);
    final folderId = _typeIndexMappings.getFolderId(docIri.typeIri);
    final filePath = docIri.id;
    final fileId = await _client.findFile(
        parentId: folderId,
        fileName: filePath,
        fileNameMayBeRelativePath: true);

    if (fileId == null) {
      // Create new file
      final created = await _client.createFile(filePath, graph,
          folderId: folderId, fileNameMayBeRelativePath: true);
      return SuccessUploadResult(created.etag);
    } else {
      // Update existing file
      return await _client.upload(fileId, graph, ifMatch: ifMatch!);
    }
  }

  @override
  Future<void> finalizeSync() async {
    // No-op for GDrive sync storage
  }
}

class GDriveRemoteStorage implements RemoteStorage {
  final RemoteId _remoteId;
  final String _userEmail;
  final GDriveClient _client;
  final GDriveTypeIndexManager _typeIndexManager;
  final ResourceLocator _resourceLocator;

  GDriveRemoteStorage({
    required GDriveClient client,
    required String userEmail,
    required GDriveTypeIndexManager typeIndexManager,
    required ResourceLocator resourceLocator,
  })  : _client = client,
        _userEmail = userEmail,
        _typeIndexManager = typeIndexManager,
        _resourceLocator = resourceLocator,
        _remoteId = RemoteId("google", userEmail);

  RemoteId get remoteId => _remoteId;

  @override
  Future<RemoteSyncStorage> createSyncStorage(
      SyncEngineConfig engineConfig) async {
    final typeIndexMappings =
        await _typeIndexManager.loadOrCreateTypeIndex(engineConfig);
    return GDriveSyncStorage(
      client: _client,
      resourceLocator: _resourceLocator,
      typeIndexMappings: typeIndexMappings,
    );
  }

  @override
  Future<bool> isAvailable() {
    // TODO: implement availability check, maybe by using some API to
    // check for online/offline status or similar.
    return Future.value(true);
  }
}

class GDriveBackend implements Backend {
  @override
  String get name => 'gdrive';
  final GDriveAuthProvider _auth;
  final GDriveClient _client;
  final GDriveTypeIndexManager _typeIndexManager;
  final ResourceLocator _resourceLocator;

  List<RemoteStorage> _remotes = [];

  factory GDriveBackend({
    required GDriveAuthProvider auth,
    required GDriveConfig config,
    IriTermFactory? iriTermFactory,
    RdfCore? rdfCore,
  }) {
    final client = GDriveClient(
      authProvider: auth,
      rdfCore: rdfCore ??
          RdfCore.withStandardCodecs(
              iriTermFactory: iriTermFactory ?? IriTerm.validated),
    );
    return GDriveBackend._(
        auth: auth,
        config: config,
        client: client,
        iriTermFactory: iriTermFactory);
  }

  GDriveBackend._({
    required GDriveAuthProvider auth,
    required GDriveClient client,
    required GDriveConfig config,
    IriTermFactory? iriTermFactory,
  })  : _auth = auth,
        _client = client,
        _typeIndexManager = GDriveTypeIndexManager(
          client: client,
          iriTermFactory: iriTermFactory ?? IriTerm.validated,
          config: config,
        ),
        _resourceLocator = LocalResourceLocator(
          iriTermFactory: iriTermFactory ?? IriTerm.validated,
        ) {
    _auth.isAuthenticatedNotifier.addListener(_authStateChanged);
    _authStateChanged();
  }

  void _authStateChanged() {
    _log.info('Authentication state changed: '
        'isAuthenticated=${_auth.isAuthenticatedNotifier.isAuthenticated}, userEmail=${_auth.userEmail}');
    if (_auth.isAuthenticatedNotifier.isAuthenticated) {
      final userEmail = _auth.userEmail;
      if (userEmail == null) {
        throw StateError(
            'User is authenticated but currentWebId is null in SolidBackend');
      }
      if (_remotes.length == 1 &&
          _remotes.first is GDriveRemoteStorage &&
          (_remotes.first as GDriveRemoteStorage)._userEmail == userEmail) {
        // No change in authentication state
        _log.fine(
            'No change in GDrive remote storage for userEmail=$userEmail');
        return;
      }
      _log.info(
          'User logged in: initializing GDrive remote storage for webId=$userEmail');
      // User logged in: initialize remote storage
      _remotes = [
        GDriveRemoteStorage(
          userEmail: userEmail,
          client: _client,
          resourceLocator: _resourceLocator,
          typeIndexManager: _typeIndexManager,
        )
      ];
    } else {
      _log.info('User logged out: clearing Solid remote storage');
      // User logged out: clear remote storage
      _remotes = [];
    }
  }

  @override
  List<RemoteStorage> get remotes => [];

  @override
  Future<void> dispose() async {
    _auth.isAuthenticatedNotifier.removeListener(_authStateChanged);
  }
}
