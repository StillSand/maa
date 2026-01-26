import requests
import json
import sys
import os

def official():
    url = 'https://ak.hypergryph.com/downloads/android_lastest'
    headers = requests.head(url).headers
    location = headers.get('location')
    return location

def bili():
    url = 'https://line1-h5-pc-api.biligame.com/game/detail/gameinfo?game_base_id=101772'
    res = requests.get(url)
    link = json.loads(res.text)['data']['android_download_link']
    return link

if __name__ == '__main__':
    client_type = sys.argv[1]
    if client_type == 'Official':
        link = official()
    elif client_type == 'Bilibili':
        link = bili()
    print(link)
    os.system('wget ' + link + ' -O arknights.apk --quiet')