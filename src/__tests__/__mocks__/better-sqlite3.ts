// __mocks__/better-sqlite3.ts

const mockDb = {
  prepare: jest.fn(),
  run: jest.fn(),
  get: jest.fn(),
  all: jest.fn(),
  exec: jest.fn(),
};

export default mockDb;