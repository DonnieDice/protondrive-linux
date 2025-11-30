const actualFs = jest.requireActual('fs');
module.exports = {
  ...actualFs,
  readdirSync: jest.fn(),
  readFileSync: jest.fn(),
};