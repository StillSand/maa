import subprocess
import toml
import os
import pathlib

client_type = os.getenv("CLIENT_TYPE")

config = toml.load(str(pathlib.Path.home())+'/.config/maa/tasks/daily.toml')
for i in config['tasks']:
    if 'params' in i:
        if 'client_type' in i['params']:
            i['params']['client_type'] = client_type
with open(str(pathlib.Path.home())+'/.config/maa/tasks/daily.toml', 'w') as f:
    toml.dump(config, f)

log = ""
process = subprocess.Popen("maa run daily", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
flag_trace = False
with process.stderr:
    for line in process.stderr:
        log += line
        if '[' in line and ']' in line:
            if 'TRACE' in line[line.find('[')+1:line.find(']')]:
                flag_trace = True
            else:
                flag_trace = False
        if not flag_trace:
            os.system('echo -n "' + line + '"')
process.wait()
output, error = process.communicate()
process.kill()

print(output)
summary = output[output.find('\n')+1:]
summary_list = summary.splitlines()
summary_msg = ""
for i in range(len(summary_list)):
    line = summary_list[i]
    if line.count('-') > len(line)*0.75:
        summary_msg += summary_list[i+1] + "\n"

step_summary = "# Summary\n```\n" + summary[summary.find('\n')+1:] + "```\n# Log\n```\n" + log + "```\n"

with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f :
    print(step_summary, file=f)

with open('asst.log', 'w') as f:
    f.write(log)

with open('msg', 'w') as f:
    f.write(summary_msg)
