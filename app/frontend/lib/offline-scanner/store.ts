// A small key/value store over IndexedDB for the offline scanner: the
// snapshot (per user and organization) and the queue of scans to send (per
// user). IndexedDB works on plain-HTTP installs too, unlike service workers.

const DB_NAME = 'makerstorage-offline'
const STORE = 'kv'

let opening: Promise<IDBDatabase> | null = null

function database(): Promise<IDBDatabase> {
  opening ??= new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  }).catch((error: unknown) => {
    opening = null
    throw error
  })
  return opening
}

async function transaction<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  const db = await database()
  return new Promise<T | undefined>((resolve, reject) => {
    const tx = db.transaction(STORE, mode)
    const request = run(tx.objectStore(STORE))
    tx.oncomplete = () => resolve(request ? request.result : undefined)
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}

export function getItem<T>(key: string): Promise<T | undefined> {
  return transaction<T>('readonly', (store) => store.get(key) as IDBRequest<T>)
}

export async function setItem<T>(key: string, value: T): Promise<void> {
  await transaction('readwrite', (store) => { store.put(value, key) })
}

/** Reads, changes and writes one key in a single transaction, so two tabs can't lose each other's writes. */
export async function updateItem<T>(key: string, change: (current: T | undefined) => T): Promise<T> {
  const db = await database()
  return new Promise<T>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite')
    const store = tx.objectStore(STORE)
    let next: T
    const read = store.get(key)
    read.onsuccess = () => {
      next = change(read.result as T | undefined)
      store.put(next, key)
    }
    tx.oncomplete = () => resolve(next)
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}

/** Deletes every key starting with `prefix`. */
export async function deletePrefix(prefix: string): Promise<void> {
  await transaction('readwrite', (store) => {
    store.delete(IDBKeyRange.bound(prefix, `${prefix}￿`))
  })
}
