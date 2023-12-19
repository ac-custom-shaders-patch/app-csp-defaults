// Simplest server for exchanging setups with comments and likes. Uses uniquely generated on client side user keys for user identification (adding sign-in form with passwords 
// seems a bit overkilly at this point). Stores data in sqlite database.
const withModeration = false; // If needed, there is a thing for moderators to be able to remove content and ban people, moderator privileges are granted through console.
const serverPort = 12016; // A few of things like that are happily running on my VPS somewhere out there, sharing ports between each other.

const crypto = require('crypto');
const restify = require('restify');
const db = require('better-sqlite3')('data.db', {});
db.pragma('journal_mode = WAL');

db.exec(`CREATE TABLE IF NOT EXISTS table_setups (setupID INTEGER PRIMARY KEY, createdDate INTEGER, carID TEXT, trackID TEXT, name TEXT, userID TEXT, userName TEXT, data TEXT, statLikes INTEGER, statDislikes INTEGER, statDownloads INTEGER, statComments INTEGER);
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

CREATE TABLE IF NOT EXISTS table_setuplikes (likeID INTEGER PRIMARY KEY, setupID INTEGER, userID TEXT, carID TEXT, direction INTEGER);
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

const dbGetLastID = db.prepare('SELECT last_insert_rowid()').pluck();
const dbGetListFn = (function (filterBy, orderBy){
  filterBy = filterBy.filter(x => x);
  const key = filterBy.join(';') + ';' + orderBy;
  return this[key] || (this[key] = db.prepare(`SELECT setupID, createdDate, carID, trackID, name, userID, userName, statLikes, statDislikes, statDownloads, statComments FROM table_setups \
    ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.map(x => `${x} = @${x}`).join(' AND ')} ORDER BY ${orderBy || 'createdDate'} LIMIT @offset, @limit`));
}).bind({});
const dbGetCommentsFn = (function (filterBy, orderBy){
  filterBy = filterBy.filter(x => x);
  const key = filterBy.join(';') + ';' + orderBy;
  return this[key] || (this[key] = db.prepare(`SELECT commentID, createdDate, userID, userName, data, statLikes, statDislikes FROM table_comments \
    ${filterBy.length > 0 ? 'WHERE ' : ''}${filterBy.map(x => `${x} = @${x}`).join(' AND ')} ORDER BY ${orderBy || 'createdDate'} LIMIT @offset, @limit`));
}).bind({});
const dbGetItem = db.prepare('SELECT setupID, createdDate, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments FROM table_setups WHERE setupID = @setupID');
const dbGetFullItem = db.prepare('SELECT setupID, createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments FROM table_setups WHERE setupID = @setupID');
const dbGetComment = db.prepare('SELECT commentID, setupID, createdDate, userID, userName, data, statLikes, statDislikes FROM table_comments WHERE commentID = @commentID');
const dbCountRecentItems = db.prepare('SELECT COUNT(*) FROM table_setups WHERE createdDate > @now - 60').pluck();
const dbCountRecentComments = db.prepare('SELECT COUNT(*) FROM table_comments WHERE createdDate > @now - 60').pluck();
const dbInsertItem = db.prepare('INSERT INTO table_setups (createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments) VALUES \
  (@now, @carID, @trackID, @name, @userID, @userName, @data, 0, 0, 0, 0)');
const dbRestoreItem = db.prepare('INSERT INTO table_setups (createdDate, carID, trackID, name, userID, userName, data, statLikes, statDislikes, statDownloads, statComments) VALUES \
  (@createdDate, @carID, @trackID, @name, @userID, @userName, @data, @statLikes, @statDislikes, @statDownloads, @statComments)');
const dbInsertComment = db.prepare('INSERT INTO table_comments (createdDate, setupID, userID, userName, data, statLikes, statDislikes) VALUES \
  (@now, @setupID, @userID, @userName, @data, 0, 0)');
const dbDeleteItem = db.prepare('DELETE FROM table_setups WHERE setupID = @setupID');
const dbDeleteComment = db.prepare('DELETE FROM table_comments WHERE commentID = @commentID');
const dbIncrementDownloads = db.prepare('UPDATE table_setups SET statDownloads = statDownloads + 1 WHERE setupID = @setupID');
const dbClearLike = db.prepare('DELETE FROM table_setuplikes WHERE setupID = @setupID AND userID = @userID');
const dbSetLike = db.prepare('INSERT INTO table_setuplikes (setupID, userID, carID, direction) VALUES (@setupID, @userID, @carID, @direction)');
const dbUpdateLikesCount = db.prepare('UPDATE table_setups SET\
  statLikes = ( SELECT COUNT(*) FROM table_setuplikes WHERE setupID = @setupID AND direction = 1 ),\
  statDislikes = ( SELECT COUNT(*) FROM table_setuplikes WHERE setupID = @setupID AND direction = -1 ) WHERE setupID = @setupID');
const dbUpdateCommentsCount = db.prepare('UPDATE table_setups SET\
  statComments = ( SELECT COUNT(*) FROM table_comments WHERE setupID = @setupID ) WHERE setupID = @setupID');
const dbClearCommentLike = db.prepare('DELETE FROM table_commentlikes WHERE commentID = @commentID AND userID = @userID');
const dbSetCommentLike = db.prepare('INSERT INTO table_commentlikes (commentID, userID, setupID, direction) VALUES (@commentID, @userID, @setupID, @direction)');
const dbUpdateCommentLikesCount = db.prepare('UPDATE table_comments SET\
  statLikes = ( SELECT COUNT(*) FROM table_commentlikes WHERE commentID = @commentID AND direction = 1 ),\
  statDislikes = ( SELECT COUNT(*) FROM table_commentlikes WHERE commentID = @commentID AND direction = -1 ) WHERE commentID = @commentID');
const dbGetOwnLikes = db.prepare('SELECT setupID, direction FROM table_setuplikes WHERE userID = @userID AND carID = @carID');
const dbGetOwnCommentLikes = db.prepare('SELECT commentID, direction FROM table_commentlikes WHERE userID = @userID AND setupID = @setupID');
const dbUpdateItemsUserName = db.prepare('UPDATE table_setups SET userName = @userName WHERE userID = @userID');
const dbUpdateCommentsUserName = db.prepare('UPDATE table_comments SET userName = @userName WHERE userID = @userID');
const dbIsModerator = db.prepare('SELECT COUNT(*) FROM table_moderators WHERE userID = @userID').pluck();
const dbIsBanned = db.prepare('SELECT COUNT(*) FROM table_banned WHERE userID = @userID').pluck();
const dbIsAddressBanned = db.prepare('SELECT COUNT(*) FROM table_bannedaddresses WHERE userAddress = @userAddress').pluck();
const dbIsKnownAddress = db.prepare('SELECT COUNT(*) FROM table_useraddresses WHERE userID = @userID AND userAddress = @userAddress').pluck();
const dbGetAllAddresses = db.prepare('SELECT userAddress FROM table_useraddresses WHERE userID = @userID').pluck();
const dbAddAddress = db.prepare('INSERT INTO table_useraddresses (userID, userAddress) VALUES (@userID, @userAddress)');
const dbGetUserName = db.prepare('SELECT userName FROM table_usernames WHERE userID = @userID').pluck();
const dbGetUserIDByName = db.prepare('SELECT userID FROM table_usernames WHERE userName = @userName').pluck();
const dbSetUserName = db.prepare('INSERT INTO table_usernames (userID, userName) VALUES (@userID, @userName)');
const dbRemoveUserName = db.prepare('DELETE FROM table_usernames WHERE userID = @userID');

const verifyBase = 1;
const verifyUserName = 1;
const verifyModerator = 3;
const callback = (cb, verify) => {
  return (req, res, next) => {
    try {
      if (!req.headers['x-user-key']) throw new Error('Incorrect request');
      const params = Object.assign({ limit: 20 }, req.body, req.query, req.params, { 
        now: Math.floor(Date.now() / 1e3), 
        userID: crypto.createHash('sha256').update('x14MWUAu4jLZoM2Z').update(req.headers['x-user-key']).digest('base64'),
        userAddress: crypto.createHash('sha256').update('4F0e0MXr7fpEUwRs').update(req.headers['x-real-ip'] || req.socket.remoteAddress).digest('base64'),
      });
      if (verify && (dbIsBanned.get(params) || dbIsAddressBanned.get(params) || verify === verifyModerator && !dbIsModerator.get(params))) throw new Error('Incorrect request');
      if (verify && !dbIsKnownAddress.get(params)) dbAddAddress.run(params);
      if (verify === verifyUserName && params.userName){
        const knownID = dbGetUserIDByName.get(params);
        if (knownID && knownID != params.userID){
          throw new Error('Username is taken');
        }
        const knownName = dbGetUserName.get(params);
        if (knownName != params.userName){
          db.transaction(() => {
            dbRemoveUserName.run(params);
            dbSetUserName.run(params);
            dbUpdateItemsUserName.run(params);
            dbUpdateCommentsUserName.run(params);
          })();
        }
      }
      res.send(cb(params) || {});
    } catch (e){
      console.warn(e);
      res.send(400, { error: '' + e });
    }
    next();
  };
}

const server = restify.createServer().use(restify.plugins.bodyParser()).use(restify.plugins.queryParser());

// Setups
server.get('/setups', callback(params => dbGetListFn([params.carID ? 'carID' : null, params.trackID ? 'trackID' : null, params.filterUserID ? 'filterUserID' : null], params.orderBy).all(Object.assign({offset: 0}, params))))
server.get('/setups/:setupID', callback(params => dbGetItem.get(params)));
server.post('/setups', callback(params => {
  if (dbCountRecentItems.get(params) > 10) throw new Error('Please try again later');
  if (params.name === '' || params.name > 255) throw new Error('Incorrect name');
  dbInsertItem.run(params);
  return {setupID: dbGetLastID.get()};
}, verifyUserName));
const recentlyRemoved = {};
server.del('/setups/:setupID', callback(params => {
  const entry = dbGetFullItem.get(params);
  if (entry.userID != params.userID && !dbIsModerator.get(params)) throw new Error('Can’t remove entry')
  dbDeleteItem.run(params);
  recentlyRemoved[entry.setupID] = entry;
}, verifyBase));
server.post('/setups-restore/:setupID', callback(params => {
  if (recentlyRemoved[params.setupID] && recentlyRemoved[params.setupID].userID == params.userID) {
    dbRestoreItem.run(recentlyRemoved[params.setupID]);
    delete recentlyRemoved[params.setupID];
  } else {
    throw new Error('Can’t restore entry');
  }
}, verifyBase));
server.post('/setup-download-counts/:setupID', callback(params => dbIncrementDownloads.run(params)));

// Likes
server.get('/likes', callback(params => dbGetOwnLikes.all(params)));
server.patch('/likes/:setupID', callback(params => db.transaction(() => {
  dbClearLike.run(params);
  if (params.direction) dbSetLike.run(params);
  dbUpdateLikesCount.run(params);
})(), verifyBase));

// Comments
server.get('/comments', callback(params => dbGetCommentsFn([params.setupID ? 'setupID' : null, params.filterUserID ? 'filterUserID' : null], params.orderBy).all(Object.assign({offset: 0}, params))));
server.post('/comments', callback(params => {
  if (dbCountRecentComments.get(params) > 10) throw new Error('Please try again later');
  dbInsertComment.run(params);
  dbUpdateCommentsCount.run(params);
  return {commentID: dbGetLastID.get()};
}, verifyUserName))
server.del('/comments/:commentID', callback(params => {
  const entry = dbGetComment.get(params);
  if (entry.userID != params.userID && !dbIsModerator.get(params)) throw new Error('Can’t remove entry')
  dbDeleteComment.run(params);
  dbUpdateCommentsCount.run({setupID: entry.setupID});
}, verifyBase));

// Comment likes
server.get('/comment-likes', callback(params => dbGetOwnCommentLikes.all(params)));
server.patch('/comment-likes/:commentID', callback(params => db.transaction(() => {
  dbClearCommentLike.run(params);
  if (params.direction) dbSetCommentLike.run(params);
  dbUpdateCommentLikesCount.run(params);
})(), verifyBase));

// Miscellaneous
server.get('/user', callback(params => ({userID: params.userID})));
server.post('/user', callback(params => ({}), verifyUserName));

// Moderation stuff
const dbNukeItemsByUser = db.prepare('DELETE FROM table_setups WHERE userID = @nukedUserID');
const dbNukeCommentsByUser = db.prepare('DELETE FROM table_comments WHERE userID = @nukedUserID');
const dbInsertModerator = db.prepare('INSERT INTO table_moderators (userID) VALUES (@moderatorUserID)');
const dbDeleteModerator = db.prepare('DELETE FROM table_moderators WHERE userID = @moderatorUserID');
const dbListModerators = db.prepare('SELECT userID FROM table_moderators');
const dbListBanned = db.prepare('SELECT userID FROM table_banned');
const dbInsertBanned = db.prepare('INSERT INTO table_banned (userID) VALUES (@bannedUserID)');
const dbDeleteBanned = db.prepare('DELETE FROM table_banned WHERE userID = @bannedUserID');
const dbInsertAddressBanned = db.prepare('INSERT INTO table_bannedaddresses (userAddress) VALUES (@bannedUserAddress)');
const dbDeleteAddressBanned = db.prepare('DELETE FROM table_bannedaddresses WHERE userAddress = @bannedUserAddress');
server.del('/user/:nukedUserID', callback(params => (dbNukeItemsByUser.run(params), dbNukeCommentsByUser.run(params)), verifyModerator));
server.get('/banned', callback(params => dbListBanned.all(params), verifyModerator));
server.post('/banned/:bannedUserID', callback(params => {
  if (dbIsBanned({userID: params.bannedUserID})) throw new Error('Already banned');
  db.transaction(() => {
    dbInsertBanned.run(params);
    dbGetAllAddresses.all({userID: params.bannedUserID}).forEach(i => dbInsertAddressBanned.run({bannedUserAddress: i}));
  })();
}, verifyModerator));
server.del('/banned/:bannedUserID', callback(params => {
  if (!dbIsBanned({userID: params.bannedUserID})) throw new Error('Not banned to begin with');
  db.transaction(() => {
    dbDeleteBanned.run(params);
    dbGetAllAddresses.all({userID: params.bannedUserID}).forEach(i => dbDeleteAddressBanned.run({bannedUserAddress: i}));
  })();
}, verifyModerator));
server.get('/moderators', callback(params => dbListModerators.all(params), verifyModerator));
server.post('/moderators/:moderatorUserID', callback(params => dbInsertBanned.run(params), verifyModerator));
server.del('/moderators/:moderatorUserID', callback(params => dbDeleteBanned.run(params), verifyModerator));

// Stats for monitoring
const dbCountItems = db.prepare('SELECT COUNT(*) FROM table_setups').pluck();
const dbCountComments = db.prepare('SELECT COUNT(*) FROM table_comments').pluck();
const dbCountNewItems = db.prepare('SELECT name, userName, carID, trackID, statLikes, statDislikes FROM table_setups WHERE createdDate > ? ORDER BY createdDate DESC');
const dbCountNewComments = db.prepare('SELECT data, userName, statLikes, statDislikes FROM table_comments WHERE createdDate > ? ORDER BY createdDate DESC');
server.get('/stats', (req, res, next) => {
  try {
    res.send({
      setups: { total: dbCountItems.get(), recent: dbCountNewItems.all(Math.floor(Date.now() / 1e3) - 86400 * 3) },
      comments: { total: dbCountComments.get(), recent: dbCountNewComments.all(Math.floor(Date.now() / 1e3) - 86400 * 3) },
    });
  } catch (e){
    res.send({error: '' + e});
  }
  next();
});

server.listen(serverPort);

if (withModeration){
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
