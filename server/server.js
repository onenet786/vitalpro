const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const mssql = require('mssql');
const { spawn } = require('child_process');

loadEnv();

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const MYSQL_HOST = process.env.MYSQL_HOST || '127.0.0.1';
const MYSQL_PORT = parseInt(process.env.MYSQL_PORT || '3306', 10);
const MYSQL_USER = process.env.MYSQL_USER || 'root';
const MYSQL_PASSWORD = process.env.MYSQL_PASSWORD || '';
const MYSQL_DATABASE = process.env.MYSQL_DATABASE || 'vitalpro_reporting';
const DEFAULT_ADMIN_USERNAME = process.env.DEFAULT_ADMIN_USERNAME || 'admin';
const DEFAULT_ADMIN_PASSWORD = process.env.DEFAULT_ADMIN_PASSWORD || 'Admin786';

let pool;
const authSessions = new Map();

function loadEnv() {
  const envPath = path.resolve(__dirname, '..', '.env');

  if (!fs.existsSync(envPath)) {
    return;
  }

  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

async function initializeStorage() {
  const bootstrapConnection = await mysql.createConnection({
    host: MYSQL_HOST,
    port: MYSQL_PORT,
    user: MYSQL_USER,
    password: MYSQL_PASSWORD,
  });

  await bootstrapConnection.query(
    `CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE.replace(/`/g, '')}\``,
  );
  await bootstrapConnection.end();

  pool = mysql.createPool({
    host: MYSQL_HOST,
    port: MYSQL_PORT,
    user: MYSQL_USER,
    password: MYSQL_PASSWORD,
    database: MYSQL_DATABASE,
    waitForConnections: true,
    connectionLimit: 10,
  });

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_settings (
      id TINYINT NOT NULL,
      company_name VARCHAR(255) NOT NULL DEFAULT '',
      company_address TEXT NULL,
      company_logo_url TEXT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS companies (
      id INT NOT NULL AUTO_INCREMENT,
      company_name VARCHAR(255) NOT NULL,
      company_address TEXT NULL,
      company_logo_url TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS reporting_servers (
      id INT NOT NULL AUTO_INCREMENT,
      name VARCHAR(255) NOT NULL,
      host VARCHAR(255) NOT NULL,
      port INT NOT NULL DEFAULT 1433,
      database_name VARCHAR(255) NOT NULL,
      authentication_mode VARCHAR(20) NOT NULL,
      username VARCHAR(255) NULL,
      password TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS report_queries (
      id INT NOT NULL AUTO_INCREMENT,
      query_name VARCHAR(255) NOT NULL,
      query_text LONGTEXT NOT NULL,
      filters_json LONGTEXT NULL,
      show_chart_default TINYINT(1) NOT NULL DEFAULT 0,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_users (
      id INT NOT NULL AUTO_INCREMENT,
      username VARCHAR(100) NOT NULL,
      password_hash TEXT NOT NULL,
      role VARCHAR(20) NOT NULL DEFAULT 'reporting',
      assigned_company_id INT NULL,
      is_active TINYINT(1) NOT NULL DEFAULT 1,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uq_app_users_username (username)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    INSERT INTO app_settings (id, company_name, company_address, company_logo_url)
    VALUES (1, '', '', '')
    ON DUPLICATE KEY UPDATE id = id;
  `);

  await ensureDefaultAdminUser();
  await ensureOptionalSchemaColumns();
}

async function ensureOptionalSchemaColumns() {
  await ensureColumnExists(
    'report_queries',
    'filters_json',
    'ALTER TABLE report_queries ADD COLUMN filters_json LONGTEXT NULL AFTER query_text',
  );
  await ensureColumnExists(
    'app_users',
    'assigned_company_id',
    'ALTER TABLE app_users ADD COLUMN assigned_company_id INT NULL AFTER role',
  );
  await migrateLegacyCompanyProfile();
}

async function ensureColumnExists(tableName, columnName, alterStatement) {
  const [rows] = await pool.query(
    `SELECT COUNT(*) AS total
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = ?
       AND TABLE_NAME = ?
       AND COLUMN_NAME = ?`,
    [MYSQL_DATABASE, tableName, columnName],
  );

  if ((rows[0]?.total || 0) > 0) {
    return;
  }

  await pool.query(alterStatement);
}

async function migrateLegacyCompanyProfile() {
  const [companyRows] = await pool.query(
    'SELECT COUNT(*) AS total FROM companies',
  );
  if ((companyRows[0]?.total || 0) > 0) {
    return;
  }

  const [rows] = await pool.query(
    `SELECT company_name, company_address, company_logo_url
     FROM app_settings
     WHERE id = 1`,
  );
  const row = rows[0];
  if (!row) {
    return;
  }

  const name = String(row.company_name || '').trim();
  const address = String(row.company_address || '').trim();
  const logoUrl = String(row.company_logo_url || '').trim();

  if (!name && !address && !logoUrl) {
    return;
  }

  await pool.query(
    `INSERT INTO companies (company_name, company_address, company_logo_url)
     VALUES (?, ?, ?)`,
    [name || 'Primary Client', address, logoUrl],
  );
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';

    req.on('data', (chunk) => {
      body += chunk.toString();
      if (body.length > 1024 * 1024 * 2) {
        reject(createHttpError(413, 'Request body is too large.'));
      }
    });

    req.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch (_) {
        reject(createHttpError(400, 'Invalid JSON body.'));
      }
    });

    req.on('error', reject);
  });
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function normalizeRole(role) {
  return String(role || '').toLowerCase() === 'admin' ? 'admin' : 'reporting';
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(String(password || ''), salt, 64, (error, derivedKey) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(`${salt}:${derivedKey.toString('hex')}`);
    });
  });
}

async function verifyPassword(password, storedHash) {
  const [salt, expectedHash] = String(storedHash || '').split(':');
  if (!salt || !expectedHash) {
    return false;
  }

  return new Promise((resolve, reject) => {
    crypto.scrypt(String(password || ''), salt, 64, (error, derivedKey) => {
      if (error) {
        reject(error);
        return;
      }

      const expectedBuffer = Buffer.from(expectedHash, 'hex');
      resolve(
        expectedBuffer.length === derivedKey.length &&
          crypto.timingSafeEqual(expectedBuffer, derivedKey),
      );
    });
  });
}

async function ensureDefaultAdminUser() {
  const [rows] = await pool.query(
    `SELECT id
     FROM app_users
     WHERE username = ?
     LIMIT 1`,
    [String(DEFAULT_ADMIN_USERNAME || '').trim().toLowerCase()],
  );

  if (rows.length > 0) {
    return;
  }

  await pool.query(
    `INSERT INTO app_users (username, password_hash, role, is_active)
     VALUES (?, ?, 'admin', 1)`,
    [
      String(DEFAULT_ADMIN_USERNAME || '').trim().toLowerCase(),
      await hashPassword(DEFAULT_ADMIN_PASSWORD),
    ],
  );
}

async function authenticateUser(username, password) {
  const normalizedUsername = String(username || '').trim().toLowerCase();
  if (!normalizedUsername || !String(password || '')) {
    throw createHttpError(400, 'Username and password are required.');
  }

  const [rows] = await pool.query(
    `SELECT u.id,
            u.username,
            u.password_hash,
            u.role,
            u.assigned_company_id,
            c.company_name AS assigned_company_name,
            u.is_active
     FROM app_users u
     LEFT JOIN companies c ON c.id = u.assigned_company_id
     WHERE u.username = ?
     LIMIT 1`,
    [normalizedUsername],
  );

  const user = rows[0];
  if (!user || !user.is_active) {
    throw createHttpError(401, 'Invalid username or password.');
  }

  const isValidPassword = await verifyPassword(password, user.password_hash);
  if (!isValidPassword) {
    throw createHttpError(401, 'Invalid username or password.');
  }

  return {
    id: user.id,
    username: user.username,
    role: normalizeRole(user.role),
    assignedCompanyId: user.assigned_company_id,
    assignedCompanyName: user.assigned_company_name || '',
  };
}

function createSession(user) {
  const token = crypto.randomBytes(32).toString('hex');
  authSessions.set(token, {
    id: user.id,
    username: user.username,
    role: normalizeRole(user.role),
    assignedCompanyId: user.assignedCompanyId || null,
    assignedCompanyName: user.assignedCompanyName || '',
  });
  return token;
}

function readBearerToken(req) {
  const authorization = req.headers.authorization || '';
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : '';
}

function requireAuth(req) {
  const token = readBearerToken(req);
  if (!token) {
    throw createHttpError(401, 'Authentication required.');
  }

  const session = authSessions.get(token);
  if (!session) {
    throw createHttpError(401, 'Your session is no longer valid. Please sign in again.');
  }

  return { token, user: session };
}

function requireAdmin(user) {
  if (normalizeRole(user.role) !== 'admin') {
    throw createHttpError(403, 'Admin access is required for this action.');
  }
}

function validateServerPayload(payload) {
  const missing = [];

  if (!payload.name) missing.push('name');
  if (!payload.host) missing.push('host');
  if (!payload.databaseName) missing.push('databaseName');
  if (!payload.authenticationMode) missing.push('authenticationMode');

  if (payload.authenticationMode === 'sqlServer') {
    if (!payload.username) missing.push('username');
    if (!payload.password) missing.push('password');
  }

  return missing;
}

function validateQueryPayload(payload) {
  const missing = [];

  if (!payload.queryName) missing.push('queryName');
  if (!payload.queryText) missing.push('queryText');

  return missing;
}

function validateUserPayload(payload) {
  const missing = [];

  if (!payload.username) missing.push('username');
  if (!payload.role) missing.push('role');
  if (!payload.id && !payload.password) missing.push('password');

  return missing;
}

function validateCompanyPayload(payload) {
  const missing = [];

  if (!payload.companyName) missing.push('companyName');

  return missing;
}

function normalizeFilterDefinitions(filters) {
  if (!Array.isArray(filters)) {
    return [];
  }

  return filters.map((filter, index) => {
    const key = String(filter?.key || '').trim();
    const label = String(filter?.label || '').trim();
    const type = String(filter?.type || 'text').trim().toLowerCase();
    const placeholder = String(filter?.placeholder || '').trim();
    const defaultValue = String(filter?.defaultValue || '').trim();

    if (!key) {
      throw createHttpError(400, `Filter ${index + 1} is missing a key.`);
    }

    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      throw createHttpError(
        400,
        `Filter "${key}" is invalid. Use letters, numbers, and underscores only.`,
      );
    }

    if (!label) {
      throw createHttpError(400, `Filter "${key}" is missing a label.`);
    }

    if (!['text', 'number', 'date'].includes(type)) {
      throw createHttpError(
        400,
        `Filter "${key}" has an unsupported type "${type}".`,
      );
    }

    return {
      key,
      label,
      type,
      isRequired: toBoolean(filter?.isRequired),
      placeholder,
      defaultValue,
    };
  });
}

function isReadOnlyQuery(queryText) {
  const normalized = String(queryText || '')
    .trim()
    .replace(/;+$/g, '')
    .toLowerCase();

  if (!normalized || !(normalized.startsWith('select') || normalized.startsWith('with'))) {
    return false;
  }

  const blockedKeywords = [
    'insert',
    'update',
    'delete',
    'drop',
    'alter',
    'create',
    'truncate',
    'merge',
    'exec',
    'execute',
    'grant',
    'revoke',
    'backup',
    'restore',
  ];

  return !blockedKeywords.some((keyword) =>
    new RegExp(`\\b${keyword}\\b`, 'i').test(normalized),
  );
}

function toBoolean(value) {
  return value === true || value === 1 || value === '1';
}

function normalizeCellValue(value) {
  if (value == null) {
    return null;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Buffer.isBuffer(value)) {
    return value.toString('base64');
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  return value;
}

async function listCompanies() {
  const [rows] = await pool.query(
    `SELECT id, company_name, company_address, company_logo_url
     FROM companies
     ORDER BY company_name ASC, id ASC`,
  );

  return rows.map((row) => ({
    id: row.id,
    companyName: row.company_name || '',
    companyAddress: row.company_address || '',
    companyLogoUrl: row.company_logo_url || '',
  }));
}

async function getCompanyProfileForUser(user) {
  const assignedCompanyId = user?.assignedCompanyId || user?.assigned_company_id;
  if (assignedCompanyId) {
    const [rows] = await pool.query(
      `SELECT id, company_name, company_address, company_logo_url
       FROM companies
       WHERE id = ?
       LIMIT 1`,
      [assignedCompanyId],
    );
    const row = rows[0];
    if (row) {
      return {
        id: row.id,
        companyName: row.company_name || '',
        companyAddress: row.company_address || '',
        companyLogoUrl: row.company_logo_url || '',
      };
    }
  }

  const companies = await listCompanies();
  return companies[0] || {
    companyName: '',
    companyAddress: '',
    companyLogoUrl: '',
  };
}

async function listServers({ includeSecrets }) {
  const [rows] = await pool.query(
    `SELECT id, name, host, port, database_name, authentication_mode, username, password
     FROM reporting_servers
     ORDER BY name ASC, id ASC`,
  );

  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    host: row.host,
    port: row.port,
    databaseName: row.database_name,
    authenticationMode: row.authentication_mode,
    username: includeSecrets ? row.username || '' : '',
    password: includeSecrets ? row.password || '' : '',
  }));
}

async function listQueries({ includeSql }) {
  const [rows] = await pool.query(
    `SELECT id, query_name, query_text, filters_json, show_chart_default
     FROM report_queries
     ORDER BY query_name ASC, id ASC`,
  );

  return rows.map((row) => ({
    id: row.id,
    queryName: row.query_name,
    queryText: includeSql ? row.query_text : '',
    filters: parseFiltersJson(row.filters_json),
    showChartByDefault: !!row.show_chart_default,
  }));
}

function parseFiltersJson(value) {
  if (!value) {
    return [];
  }

  try {
    return normalizeFilterDefinitions(JSON.parse(value));
  } catch (_) {
    return [];
  }
}

async function loadReportingBootstrap(user) {
  return {
    companyProfile: await getCompanyProfileForUser(user),
    servers: await listServers({ includeSecrets: false }),
    queries: await listQueries({ includeSql: false }),
  };
}

async function loadAdminBootstrap() {
  return {
    companyProfile: (await listCompanies())[0] || {
      companyName: '',
      companyAddress: '',
      companyLogoUrl: '',
    },
    companies: await listCompanies(),
    servers: await listServers({ includeSecrets: true }),
    queries: await listQueries({ includeSql: true }),
    users: await listUsers(),
  };
}

async function listUsers() {
  const [rows] = await pool.query(
    `SELECT u.id,
            u.username,
            u.role,
            u.assigned_company_id,
            c.company_name AS assigned_company_name,
            u.is_active
     FROM app_users u
     LEFT JOIN companies c ON c.id = u.assigned_company_id
     ORDER BY u.username ASC, u.id ASC`,
  );

  return rows.map((row) => ({
    id: row.id,
    username: row.username,
    role: normalizeRole(row.role),
    assignedCompanyId: row.assigned_company_id,
    assignedCompanyName: row.assigned_company_name || '',
    isActive: !!row.is_active,
  }));
}

async function saveCompany(payload) {
  const companyName = String(payload.companyName || '').trim();
  const companyAddress = String(payload.companyAddress || '').trim();
  const companyLogoUrl = String(payload.companyLogoUrl || '').trim();

  if (payload.id) {
    await pool.query(
      `UPDATE companies
       SET company_name = ?,
           company_address = ?,
           company_logo_url = ?
       WHERE id = ?`,
      [companyName, companyAddress, companyLogoUrl, payload.id],
    );
    return 'Company updated successfully.';
  }

  await pool.query(
    `INSERT INTO companies (company_name, company_address, company_logo_url)
     VALUES (?, ?, ?)`,
    [companyName, companyAddress, companyLogoUrl],
  );
  return 'Company created successfully.';
}

async function deleteCompany(id) {
  const [inUseRows] = await pool.query(
    `SELECT COUNT(*) AS total
     FROM app_users
     WHERE assigned_company_id = ?`,
    [id],
  );
  if ((inUseRows[0]?.total || 0) > 0) {
    throw createHttpError(
      400,
      'This company is assigned to one or more users. Reassign those users before deleting it.',
    );
  }

  const [result] = await pool.query('DELETE FROM companies WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

async function saveServer(payload) {
  const values = [
    String(payload.name || '').trim(),
    String(payload.host || '').trim(),
    parseInt(payload.port, 10) || 1433,
    String(payload.databaseName || '').trim(),
    payload.authenticationMode === 'windows' ? 'windows' : 'sqlServer',
    String(payload.username || '').trim(),
    String(payload.password || ''),
  ];

  if (payload.id) {
    await pool.query(
      `UPDATE reporting_servers
       SET name = ?,
           host = ?,
           port = ?,
           database_name = ?,
           authentication_mode = ?,
           username = ?,
           password = ?
       WHERE id = ?`,
      [...values, payload.id],
    );
    return 'SQL server updated successfully.';
  }

  await pool.query(
    `INSERT INTO reporting_servers (
      name,
      host,
      port,
      database_name,
      authentication_mode,
      username,
      password
    ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    values,
  );

  return 'SQL server saved successfully.';
}

async function deleteServer(id) {
  const [result] = await pool.query('DELETE FROM reporting_servers WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

async function saveQuery(payload) {
  const filters = normalizeFilterDefinitions(payload.filters);
  const values = [
    String(payload.queryName || '').trim(),
    String(payload.queryText || '').trim(),
    JSON.stringify(filters),
    toBoolean(payload.showChartByDefault) ? 1 : 0,
  ];

  if (payload.id) {
    await pool.query(
      `UPDATE report_queries
       SET query_name = ?,
           query_text = ?,
           filters_json = ?,
           show_chart_default = ?
       WHERE id = ?`,
      [...values, payload.id],
    );
    return 'Report query updated successfully.';
  }

  await pool.query(
    `INSERT INTO report_queries (
      query_name,
      query_text,
      filters_json,
      show_chart_default
    )
     VALUES (?, ?, ?, ?)`,
    values,
  );

  return 'Report query saved successfully.';
}

async function deleteQuery(id) {
  const [result] = await pool.query('DELETE FROM report_queries WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

async function saveUser(payload) {
  const username = String(payload.username || '').trim().toLowerCase();
  const role = normalizeRole(payload.role);
  const assignedCompanyId = payload.assignedCompanyId
    ? parseInt(payload.assignedCompanyId, 10)
    : null;
  const isActive = toBoolean(payload.isActive) ? 1 : 0;
  const id = payload.id ? parseInt(payload.id, 10) : null;

  if (id) {
    const updates = [
      'username = ?',
      'role = ?',
      'assigned_company_id = ?',
      'is_active = ?',
    ];
    const values = [username, role, assignedCompanyId, isActive];

    if (String(payload.password || '').trim()) {
      updates.push('password_hash = ?');
      values.push(await hashPassword(payload.password));
    }

    values.push(id);
    await pool.query(
      `UPDATE app_users
       SET ${updates.join(', ')}
       WHERE id = ?`,
      values,
    );
    return 'User updated successfully.';
  }

  await pool.query(
    `INSERT INTO app_users (username, password_hash, role, assigned_company_id, is_active)
     VALUES (?, ?, ?, ?, ?)`,
    [username, await hashPassword(payload.password), role, assignedCompanyId, isActive],
  );
  return 'User created successfully.';
}

async function deleteUser(id) {
  const [result] = await pool.query('DELETE FROM app_users WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

async function getServerById(id) {
  const [rows] = await pool.query(
    `SELECT id, name, host, port, database_name, authentication_mode, username, password
     FROM reporting_servers
     WHERE id = ?
     LIMIT 1`,
    [id],
  );

  const row = rows[0];
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name,
    host: row.host,
    port: row.port,
    databaseName: row.database_name,
    authenticationMode: row.authentication_mode,
    username: row.username || '',
    password: row.password || '',
  };
}

async function getQueryById(id) {
  const [rows] = await pool.query(
    `SELECT id, query_name, query_text, filters_json, show_chart_default
     FROM report_queries
     WHERE id = ?
     LIMIT 1`,
    [id],
  );

  const row = rows[0];
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    queryName: row.query_name,
    queryText: row.query_text,
    filters: parseFiltersJson(row.filters_json),
    showChartByDefault: !!row.show_chart_default,
  };
}

async function getUserByUsername(username) {
  const [rows] = await pool.query(
    `SELECT id
     FROM app_users
     WHERE username = ?
     LIMIT 1`,
    [String(username || '').trim().toLowerCase()],
  );

  return rows[0] || null;
}

function formatDateLiteral(value) {
  const normalized = String(value || '').trim();
  if (!/^\d{2}-[A-Za-z]{3}-\d{4}$/.test(normalized)) {
    throw createHttpError(
      400,
      `Date filter "${value}" must use dd-MMM-yyyy format, for example 09-Feb-2026.`,
    );
  }

  return `'${normalized}'`;
}

function formatNumberLiteral(value, key) {
  const normalized = String(value || '').trim();
  if (!normalized) {
    return '';
  }

  if (!/^-?\d+(\.\d+)?$/.test(normalized)) {
    throw createHttpError(400, `Filter "${key}" must be a valid number.`);
  }

  return normalized;
}

function formatTextLiteral(value) {
  return `'${String(value || '').replace(/'/g, "''")}'`;
}

function toSqlLiteral(filter, value) {
  if (filter.type === 'date') {
    return formatDateLiteral(value);
  }

  if (filter.type === 'number') {
    return formatNumberLiteral(value, filter.key);
  }

  return formatTextLiteral(value);
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function applyQueryFilters(queryText, filterDefinitions, filterValues) {
  let sqlText = String(queryText || '');

  for (const filter of filterDefinitions) {
    const providedValue = filterValues?.[filter.key];
    const effectiveValue = String(
      providedValue == null || providedValue === ''
        ? filter.defaultValue || ''
        : providedValue,
    ).trim();

    if (filter.isRequired && !effectiveValue) {
      throw createHttpError(400, `Filter "${filter.label}" is required.`);
    }

    if (!effectiveValue) {
      continue;
    }

    const literal = toSqlLiteral(filter, effectiveValue);
    const tokenPattern = new RegExp(
      `'\\{\\{\\s*${escapeRegex(filter.key)}\\s*\\}\\}'|\\{\\{\\s*${escapeRegex(filter.key)}\\s*\\}\\}`,
      'g',
    );

    sqlText = sqlText.replace(tokenPattern, literal);
  }

  return sqlText;
}

async function runReport(serverId, queryId, filterValues = {}) {
  const serverConfig = await getServerById(serverId);
  if (!serverConfig) {
    throw createHttpError(404, 'Selected SQL server was not found.');
  }

  const queryConfig = await getQueryById(queryId);
  if (!queryConfig) {
    throw createHttpError(404, 'Selected query was not found.');
  }

  if (!isReadOnlyQuery(queryConfig.queryText)) {
    throw createHttpError(
      400,
      'Only read-only SELECT queries can be executed for reporting.',
    );
  }

  const queryText = applyQueryFilters(
    queryConfig.queryText,
    queryConfig.filters || [],
    filterValues,
  );

  const table = serverConfig.authenticationMode === 'windows'
      ? await runSqlcmdReportQuery(serverConfig, queryText)
      : await runMssqlQuery(serverConfig, queryText);

  return {
    serverName: serverConfig.name,
    queryName: queryConfig.queryName,
    executedAt: new Date().toISOString(),
    columns: table.columns,
    rows: table.rows,
    rowCount: table.rows.length,
  };
}

async function runMssqlQuery(serverConfig, queryText) {
  const sqlPool = new mssql.ConnectionPool({
    server: serverConfig.host,
    port: parseInt(serverConfig.port, 10) || 1433,
    database: serverConfig.databaseName,
    user: serverConfig.username,
    password: serverConfig.password,
    options: {
      encrypt: false,
      trustServerCertificate: true,
    },
    requestTimeout: 120000,
    connectionTimeout: 30000,
  });

  await sqlPool.connect();

  try {
    const result = await sqlPool.request().query(queryText);
    const recordset = result.recordset || [];
    const columns = Object.keys(result.recordset?.columns || recordset[0] || {});
    const rows = recordset.map((row) => {
      const normalized = {};
      for (const column of columns) {
        normalized[column] = normalizeCellValue(row[column]);
      }
      return normalized;
    });

    return { columns, rows };
  } catch (error) {
    throw createHttpError(
      500,
      error.message || 'Could not execute the query on SQL Server.',
    );
  } finally {
    await sqlPool.close();
  }
}

function buildSqlcmdArgs(serverConfig, queryText) {
  const args = ['-S', serverConfig.host, '-d', serverConfig.databaseName];

  if (serverConfig.authenticationMode === 'windows') {
    args.push('-E');
  } else {
    args.push('-U', serverConfig.username, '-P', serverConfig.password);
  }

  args.push('-W', '-s', '|', '-y', '0', '-Y', '0', '-Q', `SET NOCOUNT ON; ${queryText}`);
  return args;
}

function parseSqlcmdTableOutput(output) {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+$/, ''))
    .filter(Boolean)
    .filter((line) => !/^\(\d+ rows affected\)$/i.test(line));

  const separatorIndex = lines.findIndex((line) => /^[-| ]+$/.test(line));
  if (separatorIndex < 1) {
    return {
      columns: [],
      rows: [],
    };
  }

  const columns = lines[separatorIndex - 1].split('|').map((item) => item.trim());
  const dataLines = lines.slice(separatorIndex + 1);
  const rows = dataLines
    .filter((line) => line.includes('|'))
    .map((line) => {
      const parts = line.split('|');
      const row = {};
      columns.forEach((column, index) => {
        row[column] = (parts[index] || '').trim();
      });
      return row;
    });

  return { columns, rows };
}

function runSqlcmdReportQuery(serverConfig, queryText) {
  return new Promise((resolve, reject) => {
    const child = spawn('sqlcmd', buildSqlcmdArgs(serverConfig, queryText), {
      windowsHide: true,
    });

    let stdoutText = '';
    let stderrText = '';

    child.stdout.on('data', (chunk) => {
      stdoutText += chunk.toString();
    });

    child.stderr.on('data', (chunk) => {
      stderrText += chunk.toString();
    });

    child.on('error', (error) => {
      reject(
        createHttpError(
          500,
          `Could not start sqlcmd. Install SQL Server tools and make sure sqlcmd is in PATH. Details: ${error.message}`,
        ),
      );
    });

    child.on('close', (code) => {
      if (code !== 0) {
        reject(
          createHttpError(
            500,
            stderrText.trim() || stdoutText.trim() || `sqlcmd exited with code ${code}.`,
          ),
        );
        return;
      }

      resolve(parseSqlcmdTableOutput(stdoutText));
    });
  });
}

function maskSecret(value) {
  if (!value) {
    return '(empty)';
  }

  return '*'.repeat(Math.max(String(value).length, 8));
}

function logStartupSettings() {
  console.log('================ REPORTING API SETTINGS ================');
  console.log(`HOST: ${HOST}`);
  console.log(`PORT: ${PORT}`);
  console.log(`MYSQL_HOST: ${MYSQL_HOST}`);
  console.log(`MYSQL_PORT: ${MYSQL_PORT}`);
  console.log(`MYSQL_USER: ${MYSQL_USER}`);
  console.log(`MYSQL_PASSWORD: ${maskSecret(MYSQL_PASSWORD)}`);
  console.log(`MYSQL_DATABASE: ${MYSQL_DATABASE}`);
  console.log('========================================================');
}

function formatStartupError(error) {
  if (!error) {
    return 'Unknown startup error.';
  }

  const code = error.code ? ` (${error.code})` : '';
  const rawMessage = typeof error.message === 'string' ? error.message.trim() : '';

  if (rawMessage) {
    return `${rawMessage}${code}`;
  }

  if (error.code === 'ECONNREFUSED') {
    return `Could not connect to MySQL at ${MYSQL_HOST}:${MYSQL_PORT} as ${MYSQL_USER}${code}. Make sure the MySQL service is running and the .env connection settings are correct.`;
  }

  if (error.code === 'ENOTFOUND') {
    return `MySQL host "${MYSQL_HOST}" could not be resolved${code}. Check MYSQL_HOST in .env.`;
  }

  return String(error);
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = requestUrl.pathname;

  try {
    if (req.method === 'GET' && pathname === '/health') {
      const [serverRows] = await pool.query('SELECT COUNT(*) AS total FROM reporting_servers');
      const [queryRows] = await pool.query('SELECT COUNT(*) AS total FROM report_queries');

      sendJson(res, 200, {
        success: true,
        message: `Reporting API is running. Saved servers: ${serverRows[0].total}. Saved queries: ${queryRows[0].total}.`,
        savedServers: serverRows[0].total,
        savedQueries: queryRows[0].total,
        timestamp: new Date().toISOString(),
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/auth/login') {
      const payload = await readJsonBody(req);
      const user = await authenticateUser(payload.username, payload.password);
      const token = createSession(user);

      sendJson(res, 200, {
        success: true,
        message: 'Login successful.',
        token,
        user,
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/auth/logout') {
      const { token } = requireAuth(req);
      authSessions.delete(token);
      sendJson(res, 200, {
        success: true,
        message: 'Signed out successfully.',
      });
      return;
    }

    if (req.method === 'GET' && pathname === '/api/reporting/bootstrap') {
      const { user } = requireAuth(req);
      sendJson(res, 200, await loadReportingBootstrap(user));
      return;
    }

    if (req.method === 'POST' && pathname === '/api/admin/bootstrap') {
      const { user } = requireAuth(req);
      requireAdmin(user);
      sendJson(res, 200, await loadAdminBootstrap());
      return;
    }

    if (req.method === 'POST' && pathname === '/api/admin/companies') {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const payload = await readJsonBody(req);
      const missing = validateCompanyPayload(payload);

      if (missing.length > 0) {
        throw createHttpError(
          400,
          `Missing required company fields: ${missing.join(', ')}`,
        );
      }

      const message = await saveCompany(payload);
      sendJson(res, 200, {
        success: true,
        message,
      });
      return;
    }

    if (req.method === 'DELETE' && pathname.startsWith('/api/admin/companies/')) {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const id = parseInt(pathname.split('/').pop(), 10);

      if (!Number.isFinite(id)) {
        throw createHttpError(400, 'Invalid company id.');
      }

      const removed = await deleteCompany(id);
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'Company deleted successfully.' : 'Company not found.',
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/admin/servers') {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const payload = await readJsonBody(req);
      const missing = validateServerPayload(payload);

      if (missing.length > 0) {
        throw createHttpError(
          400,
          `Missing required server fields: ${missing.join(', ')}`,
        );
      }

      const message = await saveServer(payload);
      sendJson(res, 200, {
        success: true,
        message,
      });
      return;
    }

    if (req.method === 'DELETE' && pathname.startsWith('/api/admin/servers/')) {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const id = parseInt(pathname.split('/').pop(), 10);

      if (!Number.isFinite(id)) {
        throw createHttpError(400, 'Invalid server id.');
      }

      const removed = await deleteServer(id);
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'SQL server deleted successfully.' : 'SQL server not found.',
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/admin/queries') {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const payload = await readJsonBody(req);
      const missing = validateQueryPayload(payload);

      if (missing.length > 0) {
        throw createHttpError(
          400,
          `Missing required query fields: ${missing.join(', ')}`,
        );
      }

      if (!isReadOnlyQuery(payload.queryText)) {
        throw createHttpError(
          400,
          'Only read-only SELECT queries can be saved for reporting.',
        );
      }

      const message = await saveQuery(payload);
      sendJson(res, 200, {
        success: true,
        message,
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/admin/users') {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const payload = await readJsonBody(req);
      const missing = validateUserPayload(payload);

      if (missing.length > 0) {
        throw createHttpError(
          400,
          `Missing required user fields: ${missing.join(', ')}`,
        );
      }

      const normalizedUsername = String(payload.username || '').trim().toLowerCase();
      if (!/^[a-z0-9._-]{3,100}$/i.test(normalizedUsername)) {
        throw createHttpError(
          400,
          'Username must be 3-100 characters and use letters, numbers, dot, underscore, or hyphen.',
        );
      }

      const existingUser = await getUserByUsername(normalizedUsername);
      const payloadId = payload.id ? parseInt(payload.id, 10) : null;
      if (existingUser && existingUser.id !== payloadId) {
        throw createHttpError(400, 'That username is already in use.');
      }

      const message = await saveUser(payload);
      sendJson(res, 200, {
        success: true,
        message,
      });
      return;
    }

    if (req.method === 'DELETE' && pathname.startsWith('/api/admin/queries/')) {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const id = parseInt(pathname.split('/').pop(), 10);

      if (!Number.isFinite(id)) {
        throw createHttpError(400, 'Invalid query id.');
      }

      const removed = await deleteQuery(id);
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'Report query deleted successfully.' : 'Report query not found.',
      });
      return;
    }

    if (req.method === 'DELETE' && pathname.startsWith('/api/admin/users/')) {
      const { user } = requireAuth(req);
      requireAdmin(user);
      const id = parseInt(pathname.split('/').pop(), 10);

      if (!Number.isFinite(id)) {
        throw createHttpError(400, 'Invalid user id.');
      }

      if (user.id === id) {
        throw createHttpError(400, 'You cannot delete the account you are signed in with.');
      }

      const removed = await deleteUser(id);
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'User deleted successfully.' : 'User not found.',
      });
      return;
    }

    if (req.method === 'POST' && pathname === '/api/reporting/run') {
      requireAuth(req);
      const payload = await readJsonBody(req);
      const serverId = parseInt(payload.serverId, 10);
      const queryId = parseInt(payload.queryId, 10);

      if (!Number.isFinite(serverId) || !Number.isFinite(queryId)) {
        throw createHttpError(400, 'serverId and queryId are required.');
      }

      sendJson(
        res,
        200,
        await runReport(serverId, queryId, payload.filters || {}),
      );
      return;
    }

    throw createHttpError(404, 'Route not found.');
  } catch (error) {
    sendJson(res, error.statusCode || 500, {
      success: false,
      message: error.message || 'Unable to process request.',
    });
  }
});

logStartupSettings();

initializeStorage()
  .then(() => {
    server.listen(PORT, HOST, () => {
      console.log(`VitalPro Reporting API listening on http://${HOST}:${PORT}`);
      console.log(`MySQL storage ready on ${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}`);
    });
  })
  .catch((error) => {
    console.error('Failed to start API:', formatStartupError(error));
    process.exit(1);
  });
