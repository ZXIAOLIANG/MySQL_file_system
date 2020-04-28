import os
import sys
import pwd
import grp
import stat
import ctypes
import mysql.connector
from mysql.connector import Error

# how to use:
# run: pip3 install mysql-connector-python
# then execute this code with current PATH that you want to be root.
# a file or directory
# i.e Users> python3 import.py 

class Leaf:
    tree_template = "insert ignore into `tree` (hash, name, parent, inode) values (%s, %s, %s, %s)"
    data_template = "insert ignore into `data` (inode, data) values (%s, %s)"
    inode_template = "insert ignore into `inodes` values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)"
    permission_template = "insert ignore into `permission_str` (inode, permission) values (%s, %s)"
    
    def __init__(self, hash, name, parent, inode, rootdir):
        self.hash = hash
        self.name = name
        self.parent = parent
        self.inode = inode
        self.rootdir = rootdir
        
    def convertToBinaryData(self):
        # Convert digital data to binary format
        with open(self.hash, 'rb') as file:
            binaryData = file.read()
        return binaryData

    def insert_to_db(self, cursor):
        a = self.hash.replace(self.rootdir, "")
        if (a == ""):
            a = "/"
        p = self.parent.replace(self.rootdir, "")
        if (p == ""):
            p = "/"
        
        ino = ctypes.c_ulong(self.inode.st_ino).value
        
        # insert inode
        cursor.execute(self.inode_template, (
            ino,
            stat.filemode(self.inode.st_mode)[0],
            stat.filemode(self.inode.st_mode)[1],
            stat.filemode(self.inode.st_mode)[2],
            stat.filemode(self.inode.st_mode)[3],
            stat.filemode(self.inode.st_mode)[4],
            stat.filemode(self.inode.st_mode)[5],
            stat.filemode(self.inode.st_mode)[6],
            stat.filemode(self.inode.st_mode)[7],
            stat.filemode(self.inode.st_mode)[8],
            stat.filemode(self.inode.st_mode)[9],
            pwd.getpwuid(self.inode.st_uid).pw_name,
            grp.getgrgid(self.inode.st_gid).gr_name,
            self.inode.st_size,
            self.inode.st_nlink,
            int(self.inode.st_atime),
            int(self.inode.st_mtime),
            int(self.inode.st_ctime)
        ))
        
        # insert tree
        cursor.execute(self.tree_template, (a, self.name, p, ino))
        
        # if this is not a directory, insert data
        if not (stat.S_ISDIR(self.inode.st_mode) or (stat.S_ISLNK(self.inode.st_mode))):
            cursor.execute(self.data_template, (ino, self.convertToBinaryData()))
        
        cursor.execute(self.permission_template, (ino, stat.filemode(self.inode.st_mode)))

# db connection
try:
    connection = mysql.connector.connect(
        host='127.0.0.1',
        database='testenv',
        user='root',
        password='ece356' # you might need to change this
    )
    mycursor = connection.cursor()
    print("db authentication complete")
except mysql.connector.Error as error:
    print("Failed inserting BLOB data into MySQL table {}".format(error))
    sys.exit()
            
# current full directory path
cwd = os.getcwd()

# sub directories
parent_dir = "NULL"
leafs = [] #Leaf
links = [] #String

for (root, dirs, files) in os.walk(".", topdown=True, followlinks=True):
    if root == ".":
        hash = cwd
        parent = "NULL"
    else:
        hash = cwd + root[1:]
        parent = os.path.dirname(hash)

    # add current directory
    dirname = os.path.basename(hash)
    leafs.append(Leaf(hash, dirname, parent, os.lstat(hash), cwd))
    if stat.S_ISLNK(os.lstat(hash).st_mode):
        links.append(hash)
    
    for child_file in files:
        filepath = hash + "/" + child_file
        leafs.append(Leaf(filepath, child_file, hash, os.lstat(filepath), cwd))
        # if this file is a link, store them
        if stat.S_ISLNK(os.lstat(filepath).st_mode):
            links.append(filepath)

# insert nodes
for l in leafs:
    l.insert_to_db(mycursor)

for l in links:
    symlink_template = "insert into `symbolic_links` values (%s, %s);"
    a = l.replace(cwd, "")
    b = os.readlink(l).replace(cwd, "").replace("..", "")
    mycursor.execute(symlink_template, (a, b))
    
connection.commit()
mycursor.close()
connection.close()

print("done without errors")
   