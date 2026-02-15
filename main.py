from fastapi import FastAPI, HTTPException

app = FastAPI()
kv_store = {} # in-memory key-value store
# we can save this to a file for persistence if needed

@app.get("")
async def set_key_value(key: str, value: str):
    # concurrency / locking
    kv_store[key] = value
    return {"message": f"Key '{key}' set successfully."}

