# MySQL as Un*x File System

This repository stores necessary SQLs, sample data and scripts in order to create a MySQL client schema as a Un*x File System, with an interactive Shell interface written in Python.

This database design is for UWaterloo ECE356 W2020 project. 

Authors: Xiaoliang Zhou (zxiaolia), Di Lei (d5lei)

## TL;DR of Installation & Quick Start with Sample Data

1. Have both MySQL and Python3 installed, and install Python3 package `pip3 install mysql-connector-python`
2. In `create_tables_procedures.sql`, `data-only.sql`, `index.sql` specify schema name at the top of the script. (Create, Use)
3. Run `create_tables_procedures.sql`, `data-only.sql`, `index.sql` in order.
4. In `rdbsh.py`, specify your MySQL connection details for mysql-connector: host, database, user, password
5. In bash, run `python3 rdbsh.py`
6. At login page, input user credentials which can be found in authentication table. Default user: d5lei password: 19971125
7. You are in bash. Enjoy using cd/ls/find/grep :)

## Installation

First, please make sure both MySQL and Python3 are installed on your machine.

The following Python package(s) are required to be installed by pip3:
```bash
pip3 install mysql-connector-python
```

`create_tables_procedures.sql` is used for creating all necessary `tables`, `keys` and `procedures`. 
You will need to specify which schema you want to use inside the SQL script. The Sample Data uses schema name `testenv`.

Sample data can be found in `data-only.sql`, with insertion SQL scripts already provided.
However, because of BLOB data, the file's encoding prevents it be opened in IDE, and can only be executed directly. (Run SQL Script with MySQL Workbench).

indexes can be found in `index.sql`.

Procedures and Functions can be found under `proc` folder.

Other than Sample Data, user can use `import.py` to import the file system strucure from his/her un*x box. Simply execute the Python script at directory which will be the root of file system.
```bash
Leons-MacBook:testenv d5lei$ python3 import.py 
# testenv becomes root(/) in the imported file system
```

## Additional Preparations

The `Authentication` table stores username and groupname of the user in a un*x file system. Password is used for login at the shell program. 
For sample data, users have already been created and stored in the table. 

If you are using your own data, you are required to add your own credentials into `Authentication` table. Also you will need to update aliases `@root_dir` and `@user_dir` in create_tables_procedures.sql and authentication.sql.

Before executing shell program, please make sure correct database params are set in `rdbsh.py` so the shell program can connect to database:
```python
# Please fill in your mysql credentials here
connection = mysql.connector.connect(
    host='127.0.0.1',
    database='testenv',
    user='root',
    password='ece356'
)
```

## Usage

To start the shell, execute `rdbsh.py`:
```bash
python3 rdbsh.py
```

User will be greeted with a friendly interface, asking for credentials (stored in Authentication table):
```bash
Leons-MacBook:testenv d5lei$ python3 rdbsh.py
Hello!
username: d5lei # put your username here
Its nice to meet you! d5lei
password: # put your password here
+++++++++++++++++++++++++++++++++++++++
Login successful!
/>
```

After logging in, user will be at the root directory.

Usages of desired client utils (examples are shown using Sample Data):

`ls`: ls [-l] [file ..]
ls can support multiple input files or paths, `.`,`..`,`~` are supported as normal un*x file system.
space in the path is escaped using `\ `
```bash
# without option, ls the current directory
/Users/>ls
.DS_Store
d5lei
notgroup
zxiaolia

# with -l option, display detailed information, requires execute permision on the directory or read permission on the file
/Users/>ls -l
total: 957      
-rw-r--r-- 1 d5lei uw 12292 Apr 25 12:04 .DS_Store
drwxr-xr-x 11 d5lei uw 352 Apr 25 01:50 d5lei
drwxr-xr-x 11 notgroup uoft 352 Apr 25 01:51 notgroup
drwxr-xr-x 11 zxiaolia uw 352 Apr 25 01:51 zxiaolia
```

`cd`: cd cd [dir]
`.`,`..`,`~` are supported as normal un*x file system.
cd can accept at most one input, inputs after the second non-escaped space are discared. 
- e.g. `cd ~/ dir` is equivalent to `cd ~/`.
```bash
/>cd Users/d5lei
/Users/d5lei/>
```

`find`: find [DIRECTORY] [FILENAME]
space in the `DIRECTORY` is escaped using `\ `.
```bash
/Users/>find zxiaolia visible
-rw-r--r-- 1 zxiaolia uw 232 Apr 25 01:51 visible.txt
find: /Users/zxiaolia/group/visible.txt: Permission Denied      
find: /Users/zxiaolia/me/visible.txt: Permission Denied      
-rw-r--r-- 1 zxiaolia uw 232 Apr 25 01:51 visible.txt

# --help
/>find --help
man find:
find: accept the directory and (partial) name of the file being found.
returns: output the “ls -l” results for all match.
usage: find DIRECTORY FILENAME
```

`grep`: grep [-l] [PATTERN] [FILENAME]
```bash
# without option, -n by default (line number)
/Users/zxiaolia/>grep this *.txt
everyone.txt: pos 2: this line is the 1st lower case line in this file.
everyone.txt: pos 5: Two lines above this line is empty.
group.txt: pos 2: this line is the 1st lower case line in this file.
group.txt: pos 5: Two lines above this line is empty.
grep: /Users/zxiaolia/me.txt: Permission Denied
others.txt: pos 2: this line is the 1st lower case line in this file.
others.txt: pos 5: Two lines above this line is empty.


# with -l option, returns filename only
/Users/zxiaolia/>grep -l lines.*empty *.txt
everyone.txt
group.txt
grep: /Users/zxiaolia/me.txt: Permission Denied
others.txt

# --help
/>grep --help
man grep:
grep: accept the (partial) name of the file and seek the relevant pattern in the matching files.
returns: returns the (partial) name of the file matching lines inside the file.
usage: grep [-l] PATTERN [FILENAME]
default: returns filename, matched line number and matched line
-l: returns filename only
```

Additional Console Commands:
`exit` or `ctrl+d`:
```bash
/>exit
Bye!
Leons-MacBook:testenv d5lei$
```

## Simple project descriptions and approach:

The first thing we did is to create an ER model for this model. The ER diagram is stored and described in ER_Model.docx. 
As the Un*x file system has a hierarchical (or tree-like) structure, it implies a parent-child relationship. So the hierarchical relationship is stored by introducing a column `parent`

Each un*x file system object directory/file is described by an inode. 
Since file systems focuses more on data structures about the files rather to the contents of that file, we decided to store actual data in a separate table.

To match behavior of a real un*x box, we introduced user credentials and session variable so with rdbsh.py; 
Each utility functions/executables are written as procedures in mysql, which performs input parsing, error checking, permission checking and required utilities.
Also, symbolic links are supported in the symbolic_links table, hard link are supported by allowing multiple full path pointing to the same inodes in tree table.




