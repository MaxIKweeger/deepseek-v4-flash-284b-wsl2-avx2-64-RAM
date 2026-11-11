import json, urllib.request, time
words = "Le renard brun saute par-dessus le chien paresseux pendant que la lune se leve sur la colline. " * 30
def run(prompt, n):
    body = json.dumps({"messages":[{"role":"user","content":prompt}],"max_tokens":n,"temperature":0,"cache_prompt":False}).encode()
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", body, {"Content-Type":"application/json"})
    t=time.time()
    d = json.load(urllib.request.urlopen(req, timeout=900))
    tm = d["timings"]
    print(f"prompt_n={tm['prompt_n']} pp={tm['prompt_per_second']:.2f} tok/s | gen_n={tm['predicted_n']} tg={tm['predicted_per_second']:.2f} tok/s | wall={time.time()-t:.0f}s", flush=True)
print("Test 1: prompt long (~600 tok), 64 tokens generes")
run("Resume ce texte en une phrase: " + words, 64)
print("Test 2: generation 128 tokens")
run("Ecris un court poeme sur l'ocean.", 128)
