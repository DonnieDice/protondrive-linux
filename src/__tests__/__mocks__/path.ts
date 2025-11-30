const actualPath = jest.requireActual('path');
module.exports = { ...actualPath, join: jest.fn(actualPath.join) };
