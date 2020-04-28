-- use ece356_unix_fs;

DROP PROCEDURE IF EXISTS authentication;
DELIMITER //
CREATE PROCEDURE authentication (
    IN auth_username varchar(50),
    IN auth_password varchar(50),
    OUT output int)
auth: BEGIN
    if (select username from authentication where username = auth_username and password = auth_password) != '' then
        SET @@SESSION.max_sp_recursion_depth=10;
        set @current_user = auth_username;
        set @root_dir = "/";
        set @user_dir = concat("/Users/", @current_user);
        set @cd = @root_dir;
        set @current_user_group = (select group_name from authentication where username = auth_username and password = auth_password);
        set output = 0; # authentication succeeded
    else
        if (select username from authentication where username = auth_username) != '' then
            set output = 1; # the password is not correct
        else
            set output = 2; # the user does not exist
        end if;
    end if;
END //
DELIMITER ;
