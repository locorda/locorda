// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://locorda.dev',
	integrations: [
		starlight({
			title: 'Locorda Docs',
			description: 'Documentation for Locorda RDF libraries and vocabularies',
			defaultLocale: 'root',
			locales: {
				root: {
					label: 'English',
					lang: 'en',
				},
			},
			logo: {
				src: './public/favicon.svg',
			},
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/locorda' }
			],
			customCss: [
				'./src/styles/docs.css',
			],
			expressiveCode: {
				themes: ['github-light', 'github-dark'],
			},
			sidebar: [
				{
					label: '← Back to Main Site',
					link: '/',
				},
				{
					label: 'RDF Documentation',
					items: [
						{ label: 'Overview', link: '/docs/rdf/' },
						{ label: 'Core', link: '/docs/rdf/core/' },
						{ label: 'Canonicalization', link: '/docs/rdf/canonicalization/' },
						{ label: 'Mapper', link: '/docs/rdf/mapper/' },
						{ label: 'XML', link: '/docs/rdf/xml/' },
						{ label: 'Terms Generator', link: '/docs/rdf/terms-generator/' },
					],
				},
				{
					label: 'Vocabulary Documentation',
					items: [
						{ label: 'Overview', link: '/docs/vocabularies/' },
						{ label: 'Getting Started', link: '/docs/vocabularies/getting-started/' },
					],
				},
			],
		}),
	],
});
