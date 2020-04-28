import os
import sys
import pwd
import grp
import stat
import ctypes
import mysql.connector
from mysql.connector import Error
from getpass import getpass

authentication_template = "call authentication(%s,%s)"

if __name__ == "__main__":
    # db connection
    try:
        connection = mysql.connector.connect(
            host='18.220.209.131',
            database='ece356_unix_fs',
            user='root',
            password='19970331' # you might need to change this
        )
        mycursor = connection.cursor()
    except mysql.connector.Error as error:
        print("Failed to connect to the file system {}".format(error))
        sys.exit()

    print("Hello!")
    username = input("username: ")
    print("It's nice to meet you! " + username)
    password = getpass("password:")
    auth_success = False
    retry_counter = 0
    while not auth_success:
        authentication_result = 99
        authentication_result = mycursor.callproc('authentication', [username, password, authentication_result])[2]
        if authentication_result == 1:
            retry_counter += 1
            if retry_counter > 3:
                print("Authentication failed!")
                sys.exit()
            print("Authentication denied! Retry!")
            password = getpass("password:")
        elif authentication_result == 0:
            auth_success = True
            print("+++++++++++++++++++++++++++++++++++++++")
            print("Login successful!")
        else:
            print("Authentication failed!")
            sys.exit()
    while True:
        mycursor.execute("select @cd")
        cd = mycursor.fetchall()[0][0]
        try:
            cmd = input(cd + ">")
        except EOFError as e:
            # ctrl+d to exit
            break
        if cmd == "exit":
            break
        elif cmd == "":
            continue
        # print(repr(cmd))
        mycursor.callproc('exec_cmd',[cmd])
        mycursor.execute("select * from cmd_result")
        for cmd_result in mycursor.fetchall():
            print(" ".join(cmd_result))


    connection.commit()
    mycursor.close()
    connection.close()
    print("Bye!")
