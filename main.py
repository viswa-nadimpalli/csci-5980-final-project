from fastapi import FastAPI, HTTPException
import uvicorn
import asyncio
import logging
import json
import os
import atexit

app = FastAPI()

# CONFIG
DATA_FILE = "kv_store_data.json"
INTERVAL_SAVE_SECONDS = 60

# LOGGER
logger = logging.getLogger("kv_store")
logger.setLevel(logging.INFO)

_file = logging.FileHandler("kv_store.log")
_formatter = logging.Formatter(
    format='%(asctime)s %(levelname)s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
)

_file.setFormatter(_formatter)
logger.addHandler(_file)

# KV STORE
kv_store = {} # {key (str): value (str)}

# LOCKS
key_locks = {} # {key (str): lock (asyncio.Lock)}
key_locks_lock = asyncio.Lock()

save_task = asyncio.Task

async def get_lock_for_key(key):
    async with key_locks_lock:
        lock = key_locks.get(key)
        if lock is None:
            lock = asyncio.Lock()
            key_locks[key] = lock
        return lock

def save_snapshot_to_disk(snapshot):
    tmp = DATA_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snapshot, f)
    os.replace(tmp, DATA_FILE)

# save to disk
async def save_to_disk():
    try:
        snapshot = dict(kv_store)
        save_snapshot_to_disk(snapshot)
        logger.info(f"Saved snapshot")

# load from disk
def load_from_disk():
    if not os.path.exists(DATA_FILE):
        return
        
    with open(DATA_FILE, "r") as f:
        data = json.load(f)
    if isinstance(data, dict):
        kv_store = {str(k): str(v) for k, v in data.items()}
        logger.info(f"Loaded {len(kv_store)} key-value pairs from disk.")

# Saving to disk every 60 seconds
async def periodic_save():
    while True:
        await asyncio.sleep(INTERVAL_SAVE_SECONDS)

        async with key_locks_lock:
            snapshot = dict(kv_store)
        
        await asyncio.to_thread(save_snapshot_to_disk, snapshot)
            
def cleanup():
    logger.info("EXIT")
    save_to_disk()

# API ENDPOINTS
@app.post("/{key}")
async def put_key_value(key: str, value: str):
    # concurrency / locking
    async with get_lock_for_key(key):
        kv_store[key] = value
    logger.info(f"PUT key='{key}' value='{value}'")
    return {"message": f"Key '{key}' set successfully."}

@app.get("/{key}")
async def get_key_value(key: str):
    async with get_lock_for_key(key):
        if key not in kv_store:
            logger.info(f"GET key='{key}' miss")
            raise HTTPException(status_code=404, detail=f"Key '{key}' not found.")
        value = kv_store[key]
    logger.info(f"GET key='{key}' value='{value}'")
    return {"key": key, "value": value}

@app.delete("/{key}")
async def delete_key_value(key: str):
    async with get_lock_for_key(key):
        if key not in kv_store:
            raise HTTPException(status_code=404, detail=f"Key '{key}' not found.")
        del kv_store[key]
    logger.info(f"DELETE key='{key}'")
    return {"message": f"Key '{key}' deleted successfully."}

atexit.register(cleanup)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8080)