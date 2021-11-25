import subprocess
import json

result = subprocess.run(["doctl", "kubernetes", "cluster", "list", "-o", "json"], stdout=subprocess.PIPE).stdout.decode('utf-8')
data = json.loads(result)

dev = []
prod = []

for cluster in data:
  if "dev" in cluster['tags']:
    dev.append(cluster['id'])
  elif "prod" in cluster['tags']:
    prod.append(cluster['id'])

ret = json.dumps({"dev": dev, "prod": prod})
print(ret)
