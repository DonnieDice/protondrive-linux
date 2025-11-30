const actual = jest.requireActual('path');
module.exports = { ...actual, join: jest.fn(actual.join) };
