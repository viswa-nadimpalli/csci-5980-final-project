from fastapi import FastAPI, HTTPException

app = FastAPI()
kv_store = {} # in-memory key-value store
# we can save this to a file for persistence if needed

@app.post("")
async def set_key_value(key: str, value: str):
    # concurrency / locking
    kv_store[key] = value
    return {"message": f"Key '{key}' set successfully."}

@app.get("/{key}")
async def get_key_value(key: str):
    if key not in kv_store:
        raise HTTPException(status_code=404, detail=f"Key '{key}' not found.")
    return {"key": key, "value": kv_store[key]}