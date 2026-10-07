// Isolated demo project and synthetic users; never connects to production.
import {before, after, beforeEach, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, deleteDoc, getDocs, collection, serverTimestamp, Timestamp, Bytes} from 'firebase/firestore';
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
