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
					collapsed: false,
					items: [
						{ label: 'Overview', slug: 'docs/sync-engine' },
						{
							label: 'Guides',
							collapsed: false,
							items: [
								{ label: 'Getting Started', slug: 'docs/sync-engine/guides/getting-started' },
							],
						},
						{
							label: 'Core Concepts',
							collapsed: false,
							items: [
								{ label: 'Conflict Resolution', slug: 'docs/sync-engine/core-concepts/conflict-resolution' },
							],
						},
						{
							label: 'Data Modeling',
							collapsed: false,
							items: [
								{ label: 'Merge Contracts & Resource Types', slug: 'docs/sync-engine/data-modeling/merge-contracts' },
							],
						},
					],
				},
				{
					label: 'RDF Libraries',
					items: [
						{ label: 'Overview', slug: 'docs/rdf' },
					],
				},
			],
		}),
	],
});
