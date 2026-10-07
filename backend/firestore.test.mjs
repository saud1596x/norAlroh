// Isolated demo project and synthetic users; never connects to production.
import {before, after, beforeEach, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, deleteDoc, getDocs, collection, serverTimestamp, Timestamp, Bytes, writeBatch} from 'firebase/firestore';
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-noor-security',
    firestore:{host:'127.0.0.1',port:8080,rules:readFileSync('firestore.rules','utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const path = uid => `users/${uid}/private/memorization`;
const value = () => ({version:1,data:Bytes.fromUint8Array(new Uint8Array([1,2,3])),updatedAt:serverTimestamp()});
const user = uid => env.authenticatedContext(uid).firestore();

test('owner can create, read, update and delete only their backup',async () => {
  const db=user('alice'); const ref=doc(db,path('alice'));
  await assertSucceeds(setDoc(ref,value()));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(setDoc(ref,value()));
  await assertSucceeds(deleteDoc(ref));
});
test('another user cannot read, replace or delete the owner backup',async () => {
  await assertSucceeds(setDoc(doc(user('alice'),path('alice')),value()));
  const ref=doc(user('bob'),path('alice'));
  await assertFails(getDoc(ref)); await assertFails(setDoc(ref,value())); await assertFails(deleteDoc(ref));
});
test('guest cannot read, create, overwrite or delete backups',async () => {
  await assertSucceeds(setDoc(doc(user('alice'),path('alice')),value()));
  const db=env.unauthenticatedContext().firestore();
  const ref=doc(db,path('alice'));
  await assertFails(getDoc(ref)); await assertFails(setDoc(ref,value())); await assertFails(deleteDoc(ref));
  await assertFails(setDoc(doc(db,path('guest')),value()));
});
test('owner cannot list other users or access undefined private collections',async () => {
  const db=user('alice');
  await assertFails(getDocs(collection(db,'users')));
  await assertFails(getDoc(doc(db,'users/alice/private/recordings')));
  await assertFails(setDoc(doc(db,'users/alice/private/recordings'),value()));
});
test('rejects malformed payloads, extra fields, unsupported versions and client timestamps',async () => {
  const ref=doc(user('alice'),path('alice'));
  for (const payload of [
    {...value(),extra:'unexpected'}, {...value(),version:2}, {...value(),data:'not-bytes'},
    {version:1,updatedAt:serverTimestamp()}, {...value(),updatedAt:Timestamp.fromMillis(1)}
  ]) await assertFails(setDoc(ref,payload));
});
test('accepts maximum payload size and rejects one byte above it',async () => {
  const ref=doc(user('alice'),path('alice'));
  await assertSucceeds(setDoc(ref,{...value(),data:Bytes.fromUint8Array(new Uint8Array(750000))}));
  await assertFails(setDoc(ref,{...value(),data:Bytes.fromUint8Array(new Uint8Array(750001))}));
});

for (const name of ['readingState','memorization']) {
  test(`${name}: owner-only access, no guest access or empty payload`, async () => {
    const db=user('alice'), location=`users/alice/private/${name}`;
    await assertSucceeds(setDoc(doc(db,location),value()));
    await assertSucceeds(getDoc(doc(db,location)));
    await assertFails(getDoc(doc(user('bob'),location)));
    await assertFails(setDoc(doc(user('bob'),location),value()));
    await assertFails(deleteDoc(doc(user('bob'),location)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),location)));
    await assertFails(setDoc(doc(db,location),{...value(),data:Bytes.fromUint8Array(new Uint8Array(0))}));
  });
}
test('two-document sync batch is atomic and cannot include another owner', async () => {
  const db=user('alice');
  const allowed=writeBatch(db);
  allowed.set(doc(db,'users/alice/private/readingState'),value());
  allowed.set(doc(db,'users/alice/private/memorization'),value());
  await assertSucceeds(allowed.commit());
  const rejected=writeBatch(db);
  rejected.delete(doc(db,'users/alice/private/readingState'));
  rejected.set(doc(db,'users/bob/private/memorization'),value());
  await assertFails(rejected.commit());
  await assertSucceeds(getDoc(doc(db,'users/alice/private/readingState')));
});

test('deletion marker prevents another device with the same valid identity from recreating data', async () => {
  const db=user('alice'), oldDevice=user('alice');
  await assertSucceeds(setDoc(doc(db,'users/alice/private/memorization'),value()));
  await assertSucceeds(setDoc(doc(db,'users/alice/private/readingState'),value()));
  const deletion=writeBatch(db);
  deletion.set(doc(db,'accountDeletions/alice'),{deletedAt:serverTimestamp()});
  deletion.delete(doc(db,'users/alice/private/readingState'));
  deletion.delete(doc(db,'users/alice/private/memorization'));
  await assertSucceeds(deletion.commit());
  for (const name of ['memorization','readingState']) {
    await assertFails(setDoc(doc(oldDevice,`users/alice/private/${name}`),value()));
    await assertFails(getDoc(doc(oldDevice,`users/alice/private/${name}`)));
  }
  await assertFails(deleteDoc(doc(oldDevice,'accountDeletions/alice')));
  await assertFails(setDoc(doc(oldDevice,'accountDeletions/alice'),{deletedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(user('bob'),'accountDeletions/alice'),{deletedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(user('bob'),'accountDeletions/alice')));
  await assertSucceeds(getDoc(doc(db,'accountDeletions/alice')));
  // Repeating cleanup remains possible if deleting the Auth user failed once.
  await assertSucceeds(deleteDoc(doc(db,'users/alice/private/memorization')));
});

test('a batch cannot mark deletion and simultaneously recreate private data', async () => {
  const db=user('alice'), batch=writeBatch(db);
  batch.set(doc(db,'accountDeletions/alice'),{deletedAt:serverTimestamp()});
  batch.set(doc(db,'users/alice/private/memorization'),value());
  await assertFails(batch.commit());
  await assertFails(setDoc(doc(db,'accountDeletions/alice'),{deletedAt:Timestamp.fromMillis(1)}));
});
