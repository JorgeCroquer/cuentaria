import subprocess
import json

res = subprocess.run(["gh", "api", "repos/JorgeCroquer/cuentaria/issues/17"], capture_output=True, text=True)
issue_data = json.loads(res.stdout)
body = issue_data["body"]

task_list = """
- [ ] Slice 1 #18
- [ ] Slice 2 #19
- [ ] Slice 3 #20
- [ ] Slice 4 #21
- [ ] Slice 5 #22
- [ ] Slice 6 #23
- [ ] Slice 7 #24
- [ ] Slice 8 #25
"""

new_body = body + task_list

with open("/tmp/new_body.md", "w") as f:
    f.write(new_body)

subprocess.run(["gh", "issue", "edit", "17", "--body-file", "/tmp/new_body.md", "--repo", "JorgeCroquer/cuentaria"])
