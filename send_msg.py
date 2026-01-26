import requests
import os

url = os.getenv("ONEBOT_URL")
qqid=int(os.getenv("QQID"))

with open('msg', 'r') as f:
    data = {
        "message_type": "private",
        "user_id": qqid,
        "message": f.read().strip("\n")
    }
    response = requests.post(url+'/send_msg', json=data)
    print(response.json())
