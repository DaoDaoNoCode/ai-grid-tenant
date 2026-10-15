module.exports = {
  platform: 'github',
  repositories: [
    'kahowell/ai-grid-tenant'
  ],
  hostRules: [
    {
      hostType: 'docker',
      matchHost: 'quay.io',
      username: process.env.QUAY_USERNAME,
      password: process.env.QUAY_PASSWORD,
    },
  ],
};
