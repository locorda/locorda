# **Locorda: Refined Offline-First Synchronization Process**

This sketch outlines a robust, transactional synchronization flow for an offline-first environment.

### **1. User Action (Client-Side) 📱**

* **Trigger**: A user creates, updates, or deletes data within the application.  
* **Immediate Action**: The change is written directly to the **local database**. This action marks the data as "dirty" or "pending sync" by setting updatedAt and ourPhyisicalClock timestamps.

### **2. Sync Trigger 🚦**

A sync cycle is initiated by one of the following events:

* **Automatic (Throttled/Debounced)**: After a local change, a timer starts. If no new changes occur for a brief period (e.g., 5 seconds), a sync is triggered.  
* **Manual**: The user initiates a sync (e.g., "pull-to-refresh").  
* **On-Connect**: The application detects it has regained network connectivity.

### **3. Phase 0: Sync Preparation (Local Materialization)**

Before any network requests, the client prepares its local state.

* **Verify Index Item Consistency**: Ensure entries in the index items table for any "dirty" documents are up-to-date with their latest clock hash and header properties. This step confirms local consistency before network operations begin.  
* **Materialize Current Local Shard State**: For each shard in the sync, construct its **current_local_shard_state**. This is done by taking the last known version of the shard document (from the previous sync's download/upload) and applying the current set of entries from the index items table as its "application data". This in-memory document represents the complete, up-to-date local view.

### **4. Synchronization Cycle 🔄**

The core process begins, organized into distinct, sequential phases.

### **Phase A: Metadata Reconciliation & Queue Building**

1. **Sync Index Documents**:  
   * For each configured index, perform a **Conditional GET** using the locally stored ETag.  
   * **Handle Response**:  
     * **Case: 200 OK (Remote Changed)**: Download the remote index and perform a **CRDT Merge** with the local version. This merged version is now prepared for upload.  
     * **Case: 304 Not Modified (Remote Unchanged)**: If the local index has pending changes, prepare the local version for upload. If not, the index document is confirmed to be up-to-date. The upload loop for the index document is skipped, but the process continues to Step 2 to check its shards.  
     * **Case: 404 Not Found (New Index)**: Prepare the local index document for its initial upload.  
   * **Finalize with Upload Loop**: If a merge occurred or if local changes need to be uploaded, initiate a loop:  
     * **a. Conditional Upload**: **PUT** the prepared index document with the correct conditional header:  
       * To **update** an existing document, use the If-Match header with the last known ETag to prevent lost updates.  
       * To **create** a new document (when no ETag is known from a prior GET), use the If-None-Match: * header to ensure the resource does not already exist.  
     * **b. On Conflict (412 Precondition Failed)**: Another client made a concurrent change. **Restart this entire step**: re-fetch the latest version, re-merge, and retry the upload.  
     * **c. On Success**: Store the new ETag returned by the server. This ensures all clients converge on the index's state before proceeding.  
2. **Build Document Sync Queue**:  
   * For each index processed in Step 1, get its list of all referenced shards (idx:hasShard).  
   * For each shard, perform a **Conditional GET** to fetch the remote shard document and its ETag.  
   * **Handle Shard Response**: The goal is to build the Document Sync Queue and a provisional merged_shell for the shard.  
     * **Case: 200 OK (Remote Changed)**:  
       * **Perform CRDT Merge**: Merge the current_local_shard_state (from Phase 0) with the downloaded remote shard. Store this result in memory as the **merged_shell**.  
     * **Case: 304 Not Modified (Remote Unchanged)**:  
       * **The current_local_shard_state is** the merged_shell: Since the remote version is unchanged, our locally prepared state is the most current view.  
     * **Case: 404 Not Found (New or Missing Shard)**:  
       * **If local entries exist**: The current_local_shard_state is the merged_shell.  
       * **If no local entries exist**: The shard is listed in the index but has not been created by any client yet. Skip it for this cycle; the next sync will retry.  
   * **Populate the in-memory Document Sync Queue** by identifying documents that fall into the following categories:  
     * All documents referenced in the local index items table (as not deleted) which are not in the active entries of the original remote shard document.  
     * All documents referenced in both the local index items table (as not deleted) and the active entries of the remote shard document that do not share the same clockHash.  
     * **For eager synced indices only**: All documents in the active entries of the remote shard document which are not in the local index items table.

#### **Phase B: Document & Shard Finalization**

This phase processes the individual documents and then ensures the shards that index them are made consistent in a transactional manner.

1. **Process Document Sync Queue**:  
   * For each document IRI in the queue:  
     * **Download & Merge**: Perform a **Conditional GET** for the remote document using its locally stored ETag.  
       * **If 200 OK**: The remote document has changed. Download it and perform a CRDT merge with the local version.  
       * **If 304 Not Modified**: The remote document is unchanged, implying a purely local change. Proceed with the existing local version.  
       * **If 404 Not Found**: The document is new locally. Proceed with the existing local version  
     * **Save & Update Locally**: Save the merged document to the local database. Update the corresponding rows in the local index items table with the new clock hash and properties like for all document changes. This might also involve removing an item from one shard's index if the data's properties changed.  
     * **Upload (if needed)**: If the merge resulted in a new state that needs to be persisted remotely, **PUT** the merged document to the server in a retry loop (using If-Match or If-None-Match: *) to handle 412 conflicts.  
2. **Finalize Shards (Transactional Loop)**:  
   * This loop runs for each shard processed in this sync cycle.  
   * **a. Determine Final Entry Set**:  
     * From the now-updated index items table, generate the **final_entry_set** for the shard.  
     * For **onDemand** strategies, add back any "remote but not local" entries from the original remote shard to this set to prevent their deletion.  
   * **b. Reconcile and Rebuild Shard**:  
     * Take the **merged_shell** created in Phase A.  
     * Apply the final_entry_set to it. This involves adding/updating all required entries and creating/updating tombstones for any entries in the merged_shell that are *not* in the final_entry_set. This produces the final_shard_document.  
   * **c. Upload Shard**: **PUT** the final_shard_document to the server, using the ETag from Phase A in an If-Match header (or If-None-Match: * for new shards).  
   * **On Conflict (412 Precondition Failed)**: Another client has modified the shard concurrently. **Restart the process for this specific shard from Phase A, Step 2.**  
   * **On Success (200 OK)**: The remote shard is now consistent. Remove relevant tasks from the Pending Index Updates Queue.  
3. **Notify Application**:  
   * Once the sync cycle completes, notify the UI to refresh and reflect the new state.

### **Cross-Cutting Concerns**

* **State Management on Failure**: If the sync is aborted (e.g., app closes, network loss), no partial state is left behind. The Document Sync Queue is rebuilt from scratch on the next run, and the Pending Index Updates Queue ensures that previously completed document merges will eventually have their corresponding index entries updated.