// Simplest server for exchanging setups with comments and likes. Uses uniquely generated on client side user keys for user identification (adding sign-in form with passwords 
// seems a bit overkilly at this point). Stores data in sqlite database.
const withModeration = false; // If needed, there is a thing for moderators to be able to remove content and ban people, moderator privileges are granted through console.

const AppCfg = {
  name: 'Setup Exchange',
  port: { main: '/root/.sock/se.acstuff.club', alt: '/root/.sock/se.api.acstuff.ru' },
  mainID: 'carID',
  cacheDBName: 'cache.db'
};

if (process.env.EXCHANGE_MODE) {
  if (process.env.EXCHANGE_MODE === 'RALLY') {
    Object.assign(AppCfg, {
      name: 'Rally Copilot',
      port: { main: '/root/.sock/re.acstuff.club', alt: '/root/.sock/re.api.acstuff.ru' },
      mainID: 'trackID',
      cacheDBName: ':memory:'
    });
  } else if (process.env.EXCHANGE_MODE.endsWith('.json')) {
    AppCfg.port = null;
    Object.assign(AppCfg, JSON.parse('' + require('fs').readFileSync(process.env.EXCHANGE_MODE)));
  } else {
    console.warn(`Unknown server mode: ${process.env.EXCHANGE_MODE}`)
  }
}

console.log(`Launching server in ${AppCfg.name} mode`);

const crypto = require('crypto');
const verifyCSPSignature = ((store, message, signature) => {
  if (!store.key) {
    store.key = crypto.createPublicKey({
      key: Buffer.from(`MIIBoDANBgkqhkiG9w0BAQEFAAOCAY0AMIIBiAKCAYEAv255WL89kNUX4xn6oWsR6YIASm9ulWqiEmWesuRzQ+LTaaOWeN6/0AKhs7TLQOb2LF9ektX3lptLVCHUpg/RzHcbQPCn/ke7vbX8HMNZUmm5cHUvhx7VdkKjtdIuF7DWnKd81XnK2xxU8+Sh7nBaraCOb4qOw6PkP/DYsd/k1UxXzEOCWsWJ8S+LZ4P6vfcB6+PujuPhXKQ+UzQkhHo7K2wVzoMl0LGFEqby8YVPH39yAk59bQkRkOz8qVMpaPKFYB+3e4rhCbAV3+yHOKlE5QZ5PTr0L2M7mL4SlevopTen6410bFI879jgCC+lEiVLRQJRb25cUYLF2plWfmc7IhuYUyrsOieiU0p8tBLH69HrcRIxgtm22/sE9j9nAeCXYVnG5VWMwox0Pm8QyuedX2y2zRN0XdDhZ7WBIrNDDvuMDTYiB7/3NyMHKGfjZpEboZ1k7L2rRG/Plq+O6i8NBYJezZC84l2FEmMinH3JGPA8pQXYE8WsB7gDVHkHmYL9AgER`, 'base64'),
      format: 'der',
      type: 'spki',
    });
  }
  const sign = crypto.createVerify('RSA-SHA1');
  sign.update(message);
  return sign.verify(store.key, signature);
}).bind(null, {});

import { Database } from 'bun:sqlite';

const db = new Database('data.db');
db.exec(`PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS table_sessions (sessionID INTEGER PRIMARY KEY, userID TEXT, createdDate INTEGER);
CREATE INDEX IF NOT EXISTS idx_sessions_0 ON table_sessions(createdDate);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_1 ON table_sessions(userID);

CREATE TABLE IF NOT EXISTS table_setups (setupID INTEGER PRIMARY KEY, createdDate INTEGER, carID TEXT, trackID TEXT, name TEXT, userID TEXT, userName TEXT, data TEXT, statLikes INTEGER, statDislikes INTEGER, statDownloads INTEGER, statComments INTEGER);
CREATE INDEX IF NOT EXISTS idx_setups_0 ON table_setups(userID);
CREATE INDEX IF NOT EXISTS idx_setups_1 ON table_setups(carID);
CREATE INDEX IF NOT EXISTS idx_setups_2 ON table_setups(trackID);
CREATE INDEX IF NOT EXISTS idx_setups_3 ON table_setups(carID, trackID);
CREATE INDEX IF NOT EXISTS idx_setups_o_0 ON table_setups(statLikes);
CREATE INDEX IF NOT EXISTS idx_setups_o_1 ON table_setups(statDownloads);
CREATE INDEX IF NOT EXISTS idx_setups_o_2 ON table_setups(statComments);
CREATE INDEX IF NOT EXISTS idx_setups_o_3 ON table_setups(createdDate);

CREATE TABLE IF NOT EXISTS table_comments (commentID INTEGER PRIMARY KEY, createdDate INTEGER, setupID INTEGER, userID TEXT, userName TEXT, data TEXT, statLikes INTEGER, statDislikes INTEGER);
CREATE INDEX IF NOT EXISTS idx_comments_0 ON table_comments(setupID);
CREATE INDEX IF NOT EXISTS idx_comments_1 ON table_comments(userID);

CREATE TABLE IF NOT EXISTS table_setuplikes (likeID INTEGER PRIMARY KEY, setupID INTEGER, userID TEXT, ${AppCfg.mainID} TEXT, direction INTEGER);
CREATE INDEX IF NOT EXISTS idx_setuplikes_0 ON table_setuplikes(setupID);
CREATE INDEX IF NOT EXISTS idx_setuplikes_1 ON table_setuplikes(userID);
CREATE INDEX IF NOT EXISTS idx_setuplikes_2 ON table_setuplikes(direction);

CREATE TABLE IF NOT EXISTS table_commentlikes (commentLikeID INTEGER PRIMARY KEY, commentID INTEGER, userID TEXT, setupID INTEGER, direction INTEGER);
CREATE INDEX IF NOT EXISTS idx_commentlikes_0 ON table_commentlikes(commentID);
CREATE INDEX IF NOT EXISTS idx_commentlikes_1 ON table_commentlikes(userID);
CREATE INDEX IF NOT EXISTS idx_commentlikes_2 ON table_commentlikes(direction);
CREATE INDEX IF NOT EXISTS idx_commentlikes_3 ON table_commentlikes(setupID);

CREATE TABLE IF NOT EXISTS table_moderators (userID TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS idx_moderators_0 ON table_moderators(userID);

CREATE TABLE IF NOT EXISTS table_banned (userID TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS idx_banned_0 ON table_banned(userID);

CREATE TABLE IF NOT EXISTS table_bannedaddresses (userAddress TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS idx_bannedaddresses_0 ON table_bannedaddresses(userAddress);

CREATE TABLE IF NOT EXISTS table_usernames (userID TEXT, userName TEXT);
CREATE INDEX IF NOT EXISTS idx_usernames_0 ON table_usernames(userID);
CREATE INDEX IF NOT EXISTS idx_usernames_1 ON table_usernames(userName);

CREATE TABLE IF NOT EXISTS table_useraddresses (userID TEXT, userAddress TEXT);
CREATE INDEX IF NOT EXISTS idx_useraddresses_0 ON table_useraddresses(userID);
CREATE INDEX IF NOT EXISTS idx_useraddresses_1 ON table_useraddresses(userAddress);`);

const cache = new Database(AppCfg.cacheDBName);
cache.exec(`PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS table_cache (entryID INTEGER PRIMARY KEY, query TEXT, ${AppCfg.mainID} TEXT, data TEXT, totalCount INTEGER, lastHitTime INTEGER);
CREATE INDEX IF NOT EXISTS idx_table_cache_0 ON table_cache(lastHitTime);
CREATE INDEX IF NOT EXISTS idx_table_cache_1 ON table_cache(${AppCfg.mainID});
CREATE UNIQUE INDEX IF NOT EXISTS idx_table_cache_2 ON table_cache(query);
DELETE FROM table_cache;`);
const cacheGet = cache.prepare('UPDATE table_cache SET lastHitTime = CURRENT_TIMESTAMP WHERE entryID = $entryID AND query = $query RETURNING data, totalCount');
const cacheInsert = cache.prepare(`INSERT INTO table_cache (entryID, query, ${AppCfg.mainID}, data, totalCount, lastHitTime) VALUES ($entryID, $query, $${AppCfg.mainID}, $data, $totalCount, CURRENT_TIMESTAMP)`);
const cachePurge = cache.prepare(`DELETE FROM table_cache WHERE ${AppCfg.mainID} = $${AppCfg.mainID}`);
const cacheCleanup = cache.prepare(`DELETE FROM table_cache WHERE lastHitTime < datetime('now', '-8 hours')`);
const cacheSize = cache.prepare(`SELECT COUNT(*) FROM table_cache`);
const cacheStats = {hits: 0, misses: 0};
const profileStats = {};

setInterval(() => {
  cacheCleanup.run();
}, 8.13 * 60 * 60 * 1e3)

const utils = {
  now: () => Math.floor(Date.now() / 1e3),
  computeUserID: (value) => new Bun.CryptoHasher('sha256').update('x14MWUAu4jLZoM2Z').update(value).digest('base64'),
  userID(req) {
    const sessionID = req.headers.get('x-session-id');
    if (sessionID != null) {
      const row = dbGetUserIDBySession.get({'$sessionID': parseInt(sessionID, 36)});
      if (!row) {
        throw new Error('Invalid session ID');
      }
      return row.userID;
    }

    // TODO: Once everybody is updated, make sure to only use x-user-key in /session requests!
    return this.computeUserID(req.headers.get('x-user-key'));
  },
  userAddress: (req, ip) => new Bun.CryptoHasher('sha256').update('4F0e0MXr7fpEUwRs').update(req.headers.get('x-real-ip') || ip).digest('base64'),
  profileTask: task => {
    let totalTime = 0;
    let started;
    const dst = {avgTime: 0, maxTime: 0, hits: 0};
    profileStats[task] = dst;
    return {
      start() {
        started = Bun.nanoseconds();
      },
      end() {
        const time = Bun.nanoseconds() - started;
        dst.avgTime = (totalTime += time) / ++dst.hits;
        dst.maxTime = Math.max(dst.maxTime * 0.99, time);
      }
    }
  }
};

function dbQuery(method, query) {
  let searchQuery = false;
  const getParamSource = (key) => {
    if (utils[key]) return `p._request ? utils.${key}(p._request, p._ip) : p.${key}`;
    if (key === 'offset') return 'p.offset||0';
    if (key === 'limit') return 'p.limit||20';
    if (key === 'search') return (searchQuery = true), '`%${p.search}%`';
    return `p.${key}`;
  };
  const convert = new Function('utils', 'p', `return {${Object.keys([].reduce.call(query.match(/@\w+/g) || [], (p, c) => (p[c] = true, p), {})).map(x => `'${x}':(${getParamSource(x.substring(1))})`).join(',')}}`).bind(null, utils);
  const stmt = searchQuery ? db.query(query) : db.prepare(query);
  const unwrap = v => v && v[0] ? v[0][0] : null;
  const task = utils.profileTask(query);
  const profile = searchQuery ? fn => fn : fn => {
    return p => {
      task.start();
      const ret = fn(p);
      task.end();
      return ret;
    };
  };
  // console.log(`New query: ${query}`);
  return method === 'all' ? profile(p => stmt.all(convert(p)))
    : method === 'get' ? profile(p => stmt.get(convert(p)))
    : method === 'pluck' ? profile(p => unwrap(p ? stmt.values(convert(p)) : stmt.values()))
    : profile(p => stmt.run(convert(p)));
}

const all = dbQuery.bind(null, 'all');
const get = dbQuery.bind(null, 'get');
const run = dbQuery.bind(null, 'run');
const pluck = dbQuery.bind(null, 'pluck');

const dbGetLastID = pluck('SELECT last_insert_rowid()');
const dbGetUserIDBySession = db.prepare('SELECT userID FROM table_sessions WHERE sessionID = $sessionID');
const dbInsertNewSession = db.prepare('INSERT INTO table_sessions (sessionID, userID, createdDate) VALUES ($sessionID, $userID, CURRENT_TIMESTAMP) ON CONFLICT(userID) DO UPDATE SET sessionID=$sessionID, createdDate=CURRENT_TIMESTAMP');
const dbClearOlderSessions = db.prepare(`DELETE FROM table_sessions WHERE createdDate < datetime('now', '-24 hours')`);
const dbGetListFn = (function (filterBy, orderBy, search){
  if (/\b(update|delete|insert|create|select)\b/i.test(orderBy)) throw new Error('Nope');
  filterBy = filterBy.filter(x => x).map(x => `${x} = @${x}`);
  let key;
  if (search) {
    key = '';
    filterBy.push('(name LIKE @search OR userName LIKE @search)');
  } else {
    key = filterBy.join(';') + ';' + orderBy;
  }
  const cached = this[key];
  if (cached) return cached;
  const created = {
    all: all(`SELECT setupID, createdDate, carID, trackID, name, userID, userName, statLikes, statDislikes, statDownloads, statComments FROM table_setups \
    ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.join(' AND ')} ORDER BY ${orderBy || 'createdDate'} LIMIT @offset, @limit`),
    count: pluck(`SELECT COUNT(*) FROM table_setups ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.join(' AND ')}`)
  };
  if (key !== '') this[key] = created;
  return created;
}).bind({});
const dbGetCommentsFn = (function (filterBy, orderBy){
  if (/\b(update|delete|insert|create|select)\b/i.test(orderBy)) throw new Error('Nope');
  filterBy = filterBy.filter(x => x).map(x => `${x} = @${x}`);
  const key = filterBy.join(';') + ';' + orderBy;
  return this[key] || (this[key] = {
    all: all(`SELECT commentID, createdDate, userID, userName, data, statLikes, statDislikes FROM table_comments \
    ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.join(' AND ')} ORDER BY ${orderBy || 'createdDate'} LIMIT @offset, @limit`),
    count: pluck(`SELECT COUNT(*) FROM table_comments ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.join(' AND ')}`)
  });
}).bind({});
const dbGetItem = get('SELECT setupID, createdDate, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments FROM table_setups WHERE setupID = @setupID');
const dbGetFullItem = get('SELECT setupID, createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments FROM table_setups WHERE setupID = @setupID');
const dbGetComment = get('SELECT commentID, setupID, createdDate, userID, userName, data, statLikes, statDislikes FROM table_comments WHERE commentID = @commentID');
const dbCountRecentItems = pluck('SELECT COUNT(*) FROM table_setups WHERE createdDate > @now - 60');
const dbCountRecentComments = pluck('SELECT COUNT(*) FROM table_comments WHERE createdDate > @now - 60');
const dbInsertItem = run('INSERT INTO table_setups (createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments) VALUES \
  (@now, @carID, @trackID, @name, @userID, @userName, @data, 0, 0, 0, 0)');
const dbRestoreItem = run('INSERT INTO table_setups (createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments) VALUES \
  (@createdDate, @carID, @trackID, @name, @userID, @userName, @data, @statLikes, @statDislikes, @statDownloads, @statComments)');
const dbInsertComment = run('INSERT INTO table_comments (createdDate, setupID, userID, userName, data, statLikes, statDislikes) VALUES \
  (@now, @setupID, @userID, @userName, @data, 0, 0)');
const dbRestoreComment = run('INSERT INTO table_comments (commentID, setupID, createdDate, userID, userName, data, statLikes, statDislikes) VALUES \
  (@commentID, @setupID, @createdDate, @userID, @userName, @data, @statLikes, @statDislikes)');
const dbDeleteItem = run('DELETE FROM table_setups WHERE setupID = @setupID');
const dbDeleteComment = run('DELETE FROM table_comments WHERE commentID = @commentID');
const dbIncrementDownloads = run('UPDATE table_setups SET statDownloads = statDownloads + 1 WHERE setupID = @setupID');
const dbClearLike = run('DELETE FROM table_setuplikes WHERE setupID = @setupID AND userID = @userID');
const dbSetLike = run(`INSERT INTO table_setuplikes (setupID, userID, ${AppCfg.mainID}, direction) VALUES (@setupID, @userID, @${AppCfg.mainID}, @direction)`);
const dbUpdateLikesCount = get(`UPDATE table_setups SET\
  statLikes = ( SELECT COUNT(*) FROM table_setuplikes WHERE setupID = @setupID AND direction = 1 ),\
  statDislikes = ( SELECT COUNT(*) FROM table_setuplikes WHERE setupID = @setupID AND direction = -1 ) WHERE setupID = @setupID RETURNING ${AppCfg.mainID}`);
const dbUpdateCommentsCount = get(`UPDATE table_setups SET\
  statComments = ( SELECT COUNT(*) FROM table_comments WHERE setupID = @setupID ) WHERE setupID = @setupID RETURNING ${AppCfg.mainID}`);
const dbClearCommentLike = run('DELETE FROM table_commentlikes WHERE commentID = @commentID AND userID = @userID');
const dbSetCommentLike = run('INSERT INTO table_commentlikes (commentID, userID, setupID, direction) VALUES (@commentID, @userID, @setupID, @direction)');
const dbUpdateCommentLikesCount = run('UPDATE table_comments SET\
  statLikes = ( SELECT COUNT(*) FROM table_commentlikes WHERE commentID = @commentID AND direction = 1 ),\
  statDislikes = ( SELECT COUNT(*) FROM table_commentlikes WHERE commentID = @commentID AND direction = -1 ) WHERE commentID = @commentID');
const dbGetOwnLikes = all(`SELECT setupID, direction FROM table_setuplikes WHERE userID = @userID AND ${AppCfg.mainID} = @${AppCfg.mainID}`);
const dbGetOwnLikesDirect = db.prepare(`SELECT setupID, direction FROM table_setuplikes WHERE userID = $userID AND ${AppCfg.mainID} = $${AppCfg.mainID}`);
const dbGetOwnCommentLikes = all('SELECT commentID, direction FROM table_commentlikes WHERE userID = @userID AND setupID = @setupID');
const dbUpdateItemsUserName = run('UPDATE table_setups SET userName = @userName WHERE userID = @userID');
const dbUpdateCommentsUserName = run('UPDATE table_comments SET userName = @userName WHERE userID = @userID');
const dbIsModerator = pluck('SELECT COUNT(*) FROM table_moderators WHERE userID = @userID');
const dbIsBanned = pluck('SELECT COUNT(*) FROM table_banned WHERE userID = @userID');
const dbIsAddressBanned = pluck('SELECT COUNT(*) FROM table_bannedaddresses WHERE userAddress = @userAddress');
const dbIsKnownAddress = pluck('SELECT COUNT(*) FROM table_useraddresses WHERE userID = @userID AND userAddress = @userAddress');
const dbGetAllAddresses = pluck('SELECT userAddress FROM table_useraddresses WHERE userID = @userID');
const dbAddAddress = run('INSERT INTO table_useraddresses (userID, userAddress) VALUES (@userID, @userAddress)');
const dbGetUserName = pluck('SELECT userName FROM table_usernames WHERE userID = @userID');
const dbGetUserIDByName = pluck('SELECT userID FROM table_usernames WHERE userName = @userName');
const dbSetUserName = run('INSERT INTO table_usernames (userID, userName) VALUES (@userID, @userName)');
const dbRemoveUserName = run('DELETE FROM table_usernames WHERE userID = @userID');
const dbCountMainEntries = db.prepare(`SELECT COUNT(*) FROM table_setups WHERE ${AppCfg.mainID} = ?1`);

// Stats for monitoring
const dbCountItems = pluck('SELECT COUNT(*) FROM table_setups');
const dbCountComments = pluck('SELECT COUNT(*) FROM table_comments');
const dbCountNewItems = db.prepare('SELECT name, userName, carID, trackID, statLikes, statDislikes FROM table_setups WHERE createdDate > $threshold ORDER BY createdDate DESC');
const dbCountNewComments = db.prepare('SELECT data, userName, statLikes, statDislikes FROM table_comments WHERE createdDate > $threshold ORDER BY createdDate DESC');
const dbRunGC = run('DELETE FROM table_useraddresses');

let recentlyRemoved = {};
let recentlyRemovedComments = {};

const VERIFY_BASE = 1;
const VERIFY_USER_NAME = 2;
const VERIFY_MODERATOR = 3;
const TRANSACTION = 4;
const CACHED = 8;
const PARTIAL_SERVE = 16;

const router = (() => {
  const methods = ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'].reduce((p, c) => ((p[c] = ({children: {}, param: null, callback: null})), p), {});
  const responseTask = utils.profileTask('Response');
  const jsonifyMainTask = utils.profileTask('JSON.stringify (main)');
  const compressMainTask = utils.profileTask('Bun.gzipSync (main)');
  const jsonifyTask = utils.profileTask('JSON.stringify');
  const compressTask = utils.profileTask('Bun.gzipSync');
  const countTask = utils.profileTask('/count');
  function register(target, path, callback, flags) {
    if (!(flags & 3) && target != methods.GET) console.warn(`Non-GET endpoint missing verify: ${path}`);
    path.split('/').filter(Boolean).reduce((p, s) => {
      const k = s.startsWith(':') ? '' : s;
      return p.children[k] || (p.children[k] = ({children: {}, param: s.startsWith(':') ? s.substring(1) : null, callback: null}));
    }, target).callback = {fn: (flags & TRANSACTION) ? p => db.transaction(() => callback(p))() : callback, flags: flags};
  }
  function headers(totalCount){
    return {headers: totalCount != null
      ? {'Content-Type': 'application/json', 'Content-Encoding': 'gzip', 'X-Total-Count': totalCount} 
      : {'Content-Type': 'application/json', 'Content-Encoding': 'gzip'}};
  }
  async function response(req, server) {    
    const url = new URL(req.url); 
    if (!req.headers.get('x-user-key') && !req.headers.get('x-session-id')) {
      if (url.pathname.startsWith('/manage')) {
        return require('./manage')({url, req, db, profileStats, cache() { return {
          size: cacheSize.values()[0][0],
          hits: cacheStats.hits,
          misses: cacheStats.misses,
        }}, runGC() {
          dbRunGC();
          db.exec('VACUUM; PRAGMA wal_checkpoint(TRUNCATE);');
          cache.exec('VACUUM; PRAGMA wal_checkpoint(TRUNCATE);');
          recentlyRemoved = {};
          recentlyRemovedComments = {};
        }});
      }
      if (url.pathname === '/count') {
        countTask.start();
        const ret = new Response(JSON.stringify({
          count: dbCountMainEntries.values(url.searchParams.get(AppCfg.mainID))[0][0]
        }), {headers: {'Content-Type': 'application/json', 'Cache-Control': 'max-age=600, public'}});
        countTask.end();
        return ret;
      }
      return new Response('404 Not Found', {status: 404, headers: { 'X-Service-Endpoint': AppCfg.port.main }});
    }
    const ip = server.requestIP(req);
    const params = req.method === 'POST' || req.method === 'PATCH' || req.method === 'PUT'
      ? Object.assign(Object.fromEntries(url.searchParams), await req.json())
      : Object.fromEntries(url.searchParams);
    params._request = req;
    params._ip = ip ? ip.address : '?'; 
    const found = url.pathname.split('/').filter(Boolean).reduce((p, s) => {
      var c = p ? p.children[s] || p.children[''] : null;
      if (c && c.param) params[c.param] = s;
      return c;
    }, methods[req.method]);
    if (!found || !found.callback) {
      return new Response(JSON.stringify({error: `Unknown endpoint: ${req.method} ${url.pathname}`}), {status: 404, headers: {'Content-Type': 'application/json'}});
    } 
    let cacheKey;
    if ((found.callback.flags & CACHED) !== 0 && params[AppCfg.mainID] && !params.search) {
      cacheKey = Bun.hash(req.url);
      const cached = cacheGet.get({'$entryID': cacheKey, '$query': req.url});
      if (cached) {
        ++cacheStats.hits;
        return new Response(cached.data, headers(found.callback.flags & PARTIAL_SERVE ? cached.totalCount : null));
      }
    }
    if (found.callback.flags & 3) {
      if (withModeration) {
        if (dbIsBanned(params) || dbIsAddressBanned(params) || (found.callback.flags & 3) === VERIFY_MODERATOR && !dbIsModerator(params)) throw new Error('Incorrect request');
        if (!dbIsKnownAddress(params)) dbAddAddress(params);
      }
      if ((found.callback.flags & 3) === VERIFY_USER_NAME && params.userName){
        const knownID = dbGetUserIDByName(params);
        if (knownID && knownID != utils.userID(req)){
          throw new Error('Username is taken');
        }
        const knownName = dbGetUserName(params);
        if (knownName != params.userName){
          db.transaction(() => {
            dbRemoveUserName(params);
            dbSetUserName(params);
            dbUpdateItemsUserName(params);
            dbUpdateCommentsUserName(params);
          })();
        }
      }
    }  
    const totalCount = [-1];
    const data = found.callback.fn(params, totalCount) || {};
    ((found.callback.flags & CACHED) !== 0 ? jsonifyMainTask : jsonifyTask).start();
    const jsoned = JSON.stringify(data);
    ((found.callback.flags & CACHED) !== 0 ? jsonifyMainTask : jsonifyTask).end();
    ((found.callback.flags & CACHED) !== 0 ? compressMainTask : compressTask).start();
    const compressed = Bun.gzipSync(jsoned);
    ((found.callback.flags & CACHED) !== 0 ? compressMainTask : compressTask).end();
    if ((found.callback.flags & CACHED) !== 0 && params[AppCfg.mainID] && !params.search) {
      cacheInsert.run({'$entryID': cacheKey, '$query': req.url, [`$${AppCfg.mainID}`]: params[AppCfg.mainID], '$data': compressed, '$totalCount': totalCount[0]});
      ++cacheStats.misses;
    }
    return new Response(compressed, headers(found.callback.flags & PARTIAL_SERVE ? totalCount[0] : null));
  }
  Bun.serve(Object.assign({
    async fetch(req) {
      responseTask.start();
      const ret = await response(req, this);
      responseTask.end();
      return ret;
    },
    error(error) {
      console.warn(error.stack);
      return new Response(JSON.stringify({ error: '' + error }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    },
  }, typeof AppCfg.port.main === 'number' ? { port: AppCfg.port.main} : { unix: AppCfg.port.main }));
  if (AppCfg.port.alt) {
    process.nextTick(() => {
      try {
        require('fs').rmSync(AppCfg.port.alt);
        require('fs').linkSync(AppCfg.port.main, AppCfg.port.alt);
      } catch {}
    });
  }
  return {
    get(path, callback, flags = 0) { register(methods.GET, path, callback, flags); },
    post(path, callback, flags = 0) { register(methods.POST, path, callback, flags); },
    patch(path, callback, flags = 0) { register(methods.PATCH, path, callback, flags); },
    put(path, callback, flags = 0) { register(methods.PUT, path, callback, flags); },
    del(path, callback, flags = 0) { register(methods.DELETE, path, callback, flags); },
  }
})();

// Setups
router.get('/setups', (ξ, h) => {
  const filter = [ξ.carID ? 'carID' : null, ξ.trackID ? 'trackID' : null, ξ.userID ? 'userID' : null, ξ.userName ? 'userName' : null];
  const q = dbGetListFn(filter, ξ.orderBy, ξ.search);
  if (ξ[AppCfg.mainID] && !ξ.search) {
    const filterString = filter.map(x => `${x}:${ξ[x]}`).join(';');
    const cacheKey = Bun.hash(filterString);
    const cached = cacheGet.get({'$entryID': cacheKey, '$query': filterString});
    if (cached) {
      h[0] = cached.totalCount;
    } else {
      h[0] = q.count(ξ);
      cacheInsert.run({'$entryID': cacheKey, '$query': filterString, [`$${AppCfg.mainID}`]: ξ[AppCfg.mainID], '$data': '', '$totalCount': h[0]});
    }
  } else {
    h[0] = q.count(ξ);
  }
  return q.all(ξ);
}, CACHED | PARTIAL_SERVE);
router.get('/setups/:setupID', dbGetItem);
router.post('/setups', ξ => {  
  if (dbCountRecentItems(ξ) > 10) throw new Error('Please try again later');
  if (ξ.name === '' || ξ.name > 255) throw new Error('Incorrect name');
  dbInsertItem(ξ);
  cachePurge.run({[`$${AppCfg.mainID}`]: ξ[AppCfg.mainID]});
  return {setupID: dbGetLastID()};
}, VERIFY_USER_NAME);
router.del('/setups/:setupID', ξ => {
  const entry = dbGetFullItem(ξ);
  if (entry.userID != utils.userID(ξ._request) && !dbIsModerator(ξ)) throw new Error('Can’t remove entry')
  dbDeleteItem(ξ);
  cachePurge.run({[`$${AppCfg.mainID}`]: entry[AppCfg.mainID]});
  recentlyRemoved[entry.setupID] = entry;
}, VERIFY_BASE);
router.post('/setups-restore/:setupID', ξ => {
  if (recentlyRemoved[ξ.setupID] && recentlyRemoved[ξ.setupID].userID == utils.userID(ξ._request)) {
    dbRestoreItem(recentlyRemoved[ξ.setupID]);
    cachePurge.run({[`$${AppCfg.mainID}`]: recentlyRemoved[ξ.setupID][AppCfg.mainID]});
    delete recentlyRemoved[ξ.setupID];
  } else {
    throw new Error('Can’t restore entry');
  }
}, VERIFY_BASE);
router.post('/setup-download-counts/:setupID', dbIncrementDownloads);

// Likes
router.get('/likes', dbGetOwnLikes);
router.patch('/likes/:setupID', ξ => {
  dbClearLike(ξ);
  if (ξ.direction) dbSetLike(ξ);
  const id = dbUpdateLikesCount(ξ)[AppCfg.mainID];  
  cachePurge.run({[`$${AppCfg.mainID}`]: id});
}, VERIFY_BASE | TRANSACTION);

// Comments
router.get('/comments', (ξ, h) => {
  const q = dbGetCommentsFn([ξ.setupID ? 'setupID' : null, ξ.userID ? 'userID' : null], ξ.orderBy);
  h[0] = q.count(ξ);
  return q.all(ξ);
}, PARTIAL_SERVE);
router.post('/comments', ξ => {
  if (dbCountRecentComments(ξ) > 10) throw new Error('Please try again later');
  dbInsertComment(ξ);
  const id = dbUpdateCommentsCount(ξ)[AppCfg.mainID];
  cachePurge.run({[`$${AppCfg.mainID}`]: id});
  return {commentID: dbGetLastID()};
}, VERIFY_USER_NAME | TRANSACTION);
router.del('/comments/:commentID', ξ => {
  const entry = dbGetComment(ξ);
  if (entry.userID != utils.userID(ξ._request) && !dbIsModerator(ξ)) throw new Error('Can’t remove entry')
  dbDeleteComment(ξ);
  const id = dbUpdateCommentsCount({setupID: entry.setupID})[AppCfg.mainID];
  cachePurge.run({[`$${AppCfg.mainID}`]: id});
  recentlyRemovedComments[entry.commentID] = entry;
}, VERIFY_BASE | TRANSACTION);
router.post('/comments-restore/:commentID', ξ => {
  if (recentlyRemovedComments[ξ.commentID] && recentlyRemovedComments[ξ.commentID].userID == utils.userID(ξ._request)) {
    dbRestoreComment(recentlyRemovedComments[ξ.commentID]);
    const id = dbUpdateCommentsCount({setupID: recentlyRemovedComments[ξ.commentID].setupID})[AppCfg.mainID];
    cachePurge.run({[`$${AppCfg.mainID}`]: id});
    delete recentlyRemovedComments[ξ.commentID];
  } else {
    throw new Error('Can’t restore comment');
  }
}, VERIFY_BASE);

// Comment likes
router.get('/comment-likes', dbGetOwnCommentLikes);
router.patch('/comment-likes/:commentID', ξ => {
  dbClearCommentLike(ξ);
  if (ξ.direction) dbSetCommentLike(ξ);
  dbUpdateCommentLikesCount(ξ);
}, VERIFY_BASE | TRANSACTION);

// Sessions
const sessionKeys = {};
router.post('/session', ξ => {
  const userID = utils.computeUserID(ξ.userID);
  sessionKeys[userID] = {secret: new Array(4).fill(0).map(x => Math.random().toString(36).substring(2)).join(''), time: Date.now()};
  return {key: sessionKeys[userID].secret};
});
router.patch('/session', ξ => {
  const userID = utils.computeUserID(ξ.userID);
  const secretData = sessionKeys[userID];
  if (!secretData) throw new Error('/session: invalid state: 1');
  delete sessionKeys[userID];
  const headerBytes = Buffer.from(ξ.header, 'base64');
  if (headerBytes.subarray(0, ξ.userID.length).toString('ascii') !== ξ.userID) throw new Error('/session: invalid state: 2');
  const data = Buffer.concat([headerBytes, Buffer.from('{UniqueMachineKeyChecksum}', 'ascii'), Buffer.from(secretData.secret, 'ascii')]);
  if (!verifyCSPSignature(data, Buffer.from(ξ.signature, 'base64'))) throw new Error('/session: verifyCSPSignature failure');
  let sessionID;
  do {
    sessionID = crypto.randomBytes(4).readUInt32BE(0);
  } while (dbGetUserIDBySession.get({'$sessionID': sessionID}));
  // console.log(`New session ID: ${sessionID} (${sessionID.toString(36)}, user: ${userID})`);
  dbInsertNewSession.run({'$sessionID': sessionID, '$userID': userID});
  let likes = '', dislikes = '';
  for (const row of dbGetOwnLikesDirect.all({'$userID': userID, [`$${AppCfg.mainID}`]: ξ[AppCfg.mainID]})){
    if (row.direction == 1) likes += row.setupID.toString(36) + ';';
    else dislikes += row.setupID.toString(36) + ';';
  }  
  return {sessionID: sessionID.toString(36), userID: userID, likes: likes, dislikes: dislikes};
});
setInterval(() => {
  const threshold = Date.now() - 5 * 60e3;
  for (var key in sessionKeys) {
    if (sessionKeys[key].time < threshold) {
      delete sessionKeys[key];
    }
  }
}, 60 * 60e3);
setInterval(() => {
  dbClearOlderSessions.run();
}, 8.17 * 60 * 60 * 1e3);

// Miscellaneous
router.get('/user', ξ => ({userID: utils.userID(ξ._request)}));
router.post('/user', () => ({}), VERIFY_USER_NAME);

// Moderation stuff
if (withModeration){
  const dbNukeItemsByUser = run('DELETE FROM table_setups WHERE userID = @nukedUserID');
  const dbNukeCommentsByUser = run('DELETE FROM table_comments WHERE userID = @nukedUserID');
  const dbInsertModerator = run('INSERT INTO table_moderators (userID) VALUES (@moderatorUserID)');
  const dbDeleteModerator = run('DELETE FROM table_moderators WHERE userID = @moderatorUserID');
  const dbListModerators = all('SELECT userID FROM table_moderators');
  const dbListBanned = all('SELECT userID FROM table_banned');
  const dbInsertBanned = run('INSERT INTO table_banned (userID) VALUES (@bannedUserID)');
  const dbDeleteBanned = run('DELETE FROM table_banned WHERE userID = @bannedUserID');
  const dbInsertAddressBanned = run('INSERT INTO table_bannedaddresses (userAddress) VALUES (@bannedUserAddress)');
  const dbDeleteAddressBanned = run('DELETE FROM table_bannedaddresses WHERE userAddress = @bannedUserAddress');
  router.del('/user/:nukedUserID', ξ => (dbNukeItemsByUser(ξ), dbNukeCommentsByUser(ξ)), VERIFY_MODERATOR);
  router.get('/banned', ξ => dbListBanned(ξ), VERIFY_MODERATOR);
  router.post('/banned/:bannedUserID', ξ => {
    if (dbIsBanned({userID: ξ.bannedUserID})) throw new Error('Already banned');
    dbInsertBanned(ξ);
    dbGetAllAddresses({userID: ξ.bannedUserID}).forEach(i => dbInsertAddressBanned({bannedUserAddress: i}));
  }, VERIFY_MODERATOR | TRANSACTION);
  router.del('/banned/:bannedUserID', ξ => {
    if (!dbIsBanned({userID: ξ.bannedUserID})) throw new Error('Not banned to begin with');
    dbDeleteBanned(ξ);
    dbGetAllAddresses({userID: ξ.bannedUserID}).forEach(i => dbDeleteAddressBanned({bannedUserAddress: i}));
  }, VERIFY_MODERATOR | TRANSACTION);
  router.get('/moderators', ξ => dbListModerators(ξ), VERIFY_MODERATOR);
  router.post('/moderators/:moderatorUserID', ξ => dbInsertBanned(ξ), VERIFY_MODERATOR);
  router.del('/moderators/:moderatorUserID', ξ => dbDeleteBanned(ξ), VERIFY_MODERATOR);

  const rl = require('readline').createInterface({input: process.stdin, output: process.stdout});
  console.log('Enter user ID to toggle their moderator priviligies:');
  rl.on('line', answer => {
    answer = answer.trim();
    if (answer){
      (dbIsModerator.get({userID: answer}) ? dbDeleteModerator : dbInsertModerator).run({moderatorUserID: answer});
      console.log(`User ${answer} ${dbIsModerator.get({userID: answer}) ? 'got' : 'lost'} moderator privilegies`);
    }
  });
}
