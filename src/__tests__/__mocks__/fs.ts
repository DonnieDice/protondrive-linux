const actual = jest.requireActual('fs');
module.exports = {
  ...actual,
  readdirSync: jest.fn(),
  readFileSync: jest.fn(),
};