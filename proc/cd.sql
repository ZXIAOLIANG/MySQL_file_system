-- use ece356_unix_fs;

DROP PROCEDURE IF EXISTS cd;
DELIMITER //
CREATE PROCEDURE cd (
    IN path varchar(100))
cd_procedure: BEGIN
    declare temp_dir varchar(100) default '';
    declare error_code int default 0;

    drop temporary table if exists cmd_result;
    create temporary table cmd_result
    (
        result varchar(100)
    );
    if path = "--help" or path = "-h" then
        insert into cmd_result(result) values ("man cd");
        insert into cmd_result(result) values ("cd: usage: cd [dir]");
        leave cd_procedure;
    end if;
    set @@sql_mode="NO_BACKSLASH_ESCAPES";
    # cd only take one input, so dicard the input after the first non-escaped space
    set path = replace(substring_index(replace(path,"\\ ", "<>")," ", 1),"<>", " ");
    set temp_dir = parse_path(path);
    call cd_output(temp_dir,error_code);

    if error_code = 0 then
        if temp_dir = '/' then
            set @cd = temp_dir;
        else
            set @cd = concat(temp_dir,"/");
        end if;
    elseif error_code = 1 then
        insert into cmd_result(result) values (concat("cd: ", path, ": No such file or directory"));
    elseif error_code = 2 then
        insert into cmd_result(result) values (concat("cd: ", path, ": Not a directory"));
    elseif error_code = 3 then
        insert into cmd_result(result) values (concat("cd: ", path, ": Permission Denied"));
    end if;
    set @@sql_mode=@@GLOBAL.SQL_MODE;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS cd_output;
DELIMITER //
CREATE PROCEDURE cd_output (
    IN temp_dir varchar(100),
    OUT error_code int
    )
cd_output_procedure: BEGIN
    declare temp_type varchar(5) default '';
    declare temp_owner_read varchar(2) default '';
    declare temp_group_read varchar(2) default '';
    declare temp_others_read varchar(2) default '';
    declare temp_owner varchar(255) default '';
    declare temp_group varchar(255) default '';
    declare temp_target varchar(255) default '';

    select inodes.type, inodes.owner_read_permission, inodes.group_read_permission, inodes.others_read_permission, inodes.owner, inodes.`group`
            from tree inner join inodes on tree.inode = inodes.inode
            where tree.hash = temp_dir
            into temp_type, temp_owner_read, temp_group_read, temp_others_read, temp_owner, temp_group;

    if temp_type = '' then
        set error_code = 1;
    elseif temp_type = '-' then
        set error_code = 2;
    elseif temp_type = 'd' then
        if (temp_owner = @current_user and temp_owner_read = 'r') or
           (temp_group = @current_user_group and temp_group_read = 'r') or
           (temp_others_read = 'r') then
            # the directory has read permission
            set error_code = 0;
        else
            # the directory does not has read permission
            set error_code = 3;
        end if;
    elseif temp_type = 'l' then
        # this is a symbolic link, check its target's permission
        select target from symbolic_links where link = temp_dir into temp_target;
        call cd_output(temp_target, error_code);
    end if;
end//
DELIMITER ;
