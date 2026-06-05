import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'ProtonDrive Linux',
  description: 'An unofficial desktop client for Proton Drive on Linux',

  cleanUrls: true,
  base: '/protondrive-linux/',

  themeConfig: {
    logo: '/proton-drive.svg',
    siteTitle: 'ProtonDrive Linux',

    socialLinks: [
      { icon: 'github', link: 'https://github.com/DonnieDice/protondrive-linux' }
    ],

    nav: [
      { text: 'Home', link: '/' },
      { text: 'About', link: '/about' },
      { text: 'Architecture', link: '/architecture/architecture' },
      { text: 'Sync', link: '/sync/sync' },
      { text: 'CI/CD', link: '/ci-cd/ci-pipeline' },
    ],

    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'About the Project', link: '/about' },
        ],
      },
      {
        text: 'Architecture',
        items: [
          { text: 'Architecture', link: '/architecture/architecture' },
          { text: 'Requirements & Pipeline Baseline', link: '/architecture/requirements-and-pipeline' },
          { text: 'Build System', link: '/architecture/build-system' },
          { text: 'Proxy System', link: '/architecture/proxy-system' },
          { text: 'App Navigation', link: '/architecture/proton-navigation' },
        ],
      },
      {
        text: 'Sync',
        items: [
          { text: 'Two-Way Sync Notes', link: '/sync/sync' },
          { text: 'Sync System', link: '/sync/sync-system' },
          { text: 'Sync Database', link: '/sync/sync-database' },
          { text: 'Sync-DB Module', link: '/sync/sync-db-module' },
          { text: 'Live Sync Module', link: '/sync/live-sync-module' },
          { text: 'Login/Sync Runbook', link: '/sync/login-sync-regression-runbook' },
        ],
      },
      {
        text: 'Auth & WebView',
        items: [
          { text: 'Auth Module', link: '/auth/auth-module' },
          { text: 'SSO Authentication', link: '/auth/sso-authentication' },
          { text: 'WebView Configuration', link: '/webview/webview-configuration' },
          { text: 'WebView Integration', link: '/webview/webview-integration' },
          { text: 'URL Log & Storage', link: '/webview/url-log-webview-storage' },
        ],
      },
      {
        text: 'CI/CD',
        items: [
          { text: 'CI Pipeline', link: '/ci-cd/ci-pipeline' },
          { text: 'CI Pipeline Reference', link: '/ci-cd/ci-pipeline-reference' },
          { text: 'CI Authority & Mirroring', link: '/ci-cd/ci-authority-and-mirroring' },
          { text: 'CI/CD Roadmap', link: '/ci-cd/ci-cd-roadmap' },
        ],
      },
      {
        text: 'Build & Packaging',
        items: [
          { text: 'Packaging Overview', link: '/build-packaging/packaging' },
          { text: 'Build & Packaging Guide', link: '/build-packaging/build-packaging' },
          { text: 'New Package Checklist', link: '/build-packaging/new-build-checklist' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Workflow Guide', link: '/reference/workflow' },
          { text: 'Release Checklist', link: '/reference/release-checklist' },
          { text: 'Configuration', link: '/reference/configuration-reference' },
          { text: 'Blob Downloads', link: '/reference/blob-downloads' },
        ],
      },
      {
        text: 'Contributing & Community',
        items: [
          { text: 'Contributing Guide', link: '/CONTRIBUTING' },
          { text: 'Code of Conduct', link: '/CODE_OF_CONDUCT' },
          { text: 'Security Policy', link: '/SECURITY' },
          { text: 'Contributors', link: '/CONTRIBUTORS' },
        ],
      },
      {
        text: 'Debugging',
        items: [
          { text: 'Worker Login / SRI', link: '/debugging/worker-login-sri' },
        ],
      },
    ],

    footer: {
      message: 'This project is not affiliated with, endorsed by, or connected to Proton AG.',
      copyright: 'Released under the AGPL-3.0 license',
    },

    editLink: {
      pattern: 'https://github.com/DonnieDice/protondrive-linux/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    search: {
      provider: 'local',
    },
  },
})
