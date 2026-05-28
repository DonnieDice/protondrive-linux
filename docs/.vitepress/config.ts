import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'ProtonDrive Linux',
  description: 'An unofficial desktop client for Proton Drive on Linux',

  // Clean URLs without .html extension
  cleanUrls: true,

  // Base URL for GitHub Pages deployment
  base: '/protondrive-linux/',

  themeConfig: {
    // Project branding
    logo: '/proton-drive.svg',
    siteTitle: 'ProtonDrive Linux',

    // Social links
    socialLinks: [
      { icon: 'github', link: 'https://github.com/DonnieDice/protondrive-linux' }
    ],

    // Top navigation
    nav: [
      { text: 'Home', link: '/' },
      { text: 'About', link: '/about' },
      { text: 'Contributing', link: '/CONTRIBUTING' },
      { text: 'Packaging', link: '/packaging' },
    ],

    // Sidebar — mirrors the project's documentation structure
    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'About the Project', link: '/about' },
        ],
      },
      {
        text: 'Contributing',
        items: [
          { text: 'Workflow Guide', link: '/workflow' },
          { text: 'Build & Packaging', link: '/CONTRIBUTING' },
        ],
      },
      {
        text: 'Packaging & Release',
        items: [
          { text: 'Support Matrix & Policy', link: '/packaging' },
          { text: 'Release Checklist', link: '/release-checklist' },
          { text: 'New Package Checklist', link: '/new-build-checklist' },
        ],
      },
      {
        text: 'Debugging',
        items: [
          { text: 'Worker Login / SRI', link: '/debugging/worker-login-sri' },
        ],
      },
      {
        text: 'Community',
        items: [
          { text: 'Code of Conduct', link: '/CODE_OF_CONDUCT' },
          { text: 'Security Policy', link: '/SECURITY' },
          { text: 'Contributors', link: '/contributors' },
        ],
      },
    ],

    // Footer
    footer: {
      message: 'This project is not affiliated with, endorsed by, or connected to Proton AG.',
      copyright: 'Released under the AGPL-3.0 license',
    },

    // Edit link — points to the GitHub source
    editLink: {
      pattern: 'https://github.com/DonnieDice/protondrive-linux/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    // Search — built-in full-text search
    search: {
      provider: 'local',
    },
  },
})
