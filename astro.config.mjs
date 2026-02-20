// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://locorda.dev',
	integrations: [
		starlight({
			title: 'Locorda Documentation',
			description: 'Documentation for Locorda projects - Sync Engine and RDF libraries',
			disable404Route: true,
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/locorda',
				},
			],
			sidebar: [
				{
					label: 'Overview',
					items: [
						{ label: 'Introduction', slug: 'docs' },
					],
				},
				{
					label: 'Sync Engine',
					items: [
						{ label: 'Getting Started', slug: 'docs/sync-engine/getting-started' },
					],
				},
				{
					label: 'RDF Libraries',
					items: [
						{ label: 'Coming Soon', slug: 'docs/rdf' },
					],
				},
			],
		}),
	],
});
