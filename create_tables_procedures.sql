-- use schema of your choice
# CREATE DATABASE  IF NOT EXISTS testenv3;
use ece356_unix_fs;

SET NAMES utf8mb4; -- utf8

-- remove foreign keys
DROP TABLE IF EXISTS `symbolic_links`;
DROP TABLE IF EXISTS `data`;
DROP TABLE IF EXISTS `PATH`;
DROP TABLE IF EXISTS `directory`;
DROP TABLE IF EXISTS `tree`;
DROP TABLE IF EXISTS `inodes`;
DROP TABLE IF EXISTS `authentication`;
DROP TABLE IF EXISTS `permission_str`;

CREATE TABLE `PATH` (
  `command` varchar(50),
  primary key (`command`)
) ENGINE=InnoDB;
INSERT INTO PATH(command) values ('ls');
INSERT INTO PATH(command) values ('grep');
INSERT INTO PATH(command) values ('find');
INSERT INTO PATH(command) values ('cd');

CREATE TABLE `authentication` (
  `username` varchar(50),
  `password` varchar(50),
  `group_name` varchar(50),
  primary key (`username`)
) ENGINE=InnoDB;

-- ----------------------------
-- Table structure for `inodes`: represents the actual inode table
-- inode: number of inode. BIGINT
-- type: type of the inode (directory, txt, etc.). VARCHAR
-- permission: the permission bits for the inode. VARCHAR
-- owner: user id of the owner. VARCHAR
-- group: group id of the inode. VARCHAR
-- size: size of the data chunks. BIGINT
-- nlinks: number of hard links to this inode. INT
-- atime, mtime, ctime: Last accessed/modified/changed
-- ----------------------------
CREATE TABLE `inodes` (
  `inode` bigint,
  `type` char(1),
  `owner_read_permission` char(1),
  `owner_write_permission` char(1),
  `owner_exec_permission` char(1),
  `group_read_permission` char(1),
  `group_write_permission` char(1),
  `group_exec_permission` char(1),
  `others_read_permission` char(1),
  `others_write_permission` char(1),
  `others_exec_permission` char(1),
  `owner` varchar(255),
  `group` varchar(255),
  `size` bigint,
  `nlinks` int,
  `atime` int,
  `mtime` int,
  `ctime` int,
  primary key (`inode`),
  check(size > 0),
  check(nlinks > 0)
) ENGINE=InnoDB;

-- ----------------------------
-- Table structure for `tree`: represents hierarchical directory listing
-- hash: hash value of full pathname of the file. VARCHAR
-- name: name of the file (filename only). VARCHAR
-- parent: hash value of the parent directory. VARCHAR
-- ----------------------------
CREATE TABLE `tree` (
  `hash` varchar(255),
  `name` varchar(255),
  `parent` varchar(255),
  `inode` bigint,
  primary key (`hash`),
  foreign key (`inode`) references inodes(`inode`)
) ENGINE=InnoDB;


-- ----------------------------
-- Table structure for `symbolic_links`: represents soft (symbolic) link relationships of files
-- link: hash value of the linked file. VARCHAR
-- target: hash value of the target file of the link. VARCHAR
-- ----------------------------
CREATE TABLE `symbolic_links` (
  `link` varchar(255),
  `target` varchar(255),
  primary key (`link`, `target`),
  foreign key (`link`) references tree(`hash`),
  foreign key (`target`) references tree(`hash`)
) ENGINE=InnoDB;



CREATE TABLE `permission_str` (
  `inode` bigint,
  `permission` varchar(10),
  primary key (`inode`)
) ENGINE=InnoDB;

-- ----------------------------
-- Table structure for `data`: represents data blocks stored in an inode
-- data: data block of corresponding inode. BLOB
-- ----------------------------
CREATE TABLE `data` (
  `inode` bigint,
  `data` blob DEFAULT NULL,
  primary key (`inode`),
  foreign key (`inode`) references inodes(`inode`)
) ENGINE=InnoDB;

-- ----------------------------
--  Table structure for `directory`: represents relationships between name and inode
-- ----------------------------
# CREATE TABLE `directory` (
#   `hash` varchar(255),
#   `inode` bigint,
#   primary key (`hash`),
#   foreign key (`hash`) references tree(`hash`),
#   foreign key (`inode`) references inodes(`inode`)
# ) ENGINE=InnoDB;

-- ----------------------------
--  Creating, Running all procedures
-- ----------------------------
-- ----------------------------
-- authentication.sql
-- ----------------------------
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

-- ----------------------------
-- exec_cmd.sql
-- ----------------------------
DROP PROCEDURE IF EXISTS exec_cmd;
DELIMITER //
CREATE PROCEDURE exec_cmd (
    IN cmd varchar(100))
execute_cmd: BEGIN
    declare executable varchar(10) default '';
    declare input varchar(100) default '';
    set cmd = TRIM(TRAILING ' ' FROM REGEXP_REPLACE(cmd, '[[:space:]]+', ' ')); # remove duplicate space
    if instr(cmd, " ") != 0 then
        set input = substring(cmd, instr(cmd, " ")+1);
    else
        set input = substring(cmd, 0);
    end if;
    select command from PATH where command = substring_index(cmd,' ', 1) into executable;
    case executable
            when "ls" then
                call ls(input);
            when "cd" then
                call cd(input);
            when "grep" then
                call grep(input);
            when "find" then
                call find(input);
            else
                drop temporary table if exists cmd_result;
                create temporary table cmd_result
                (
                    result varchar(100) not null
                );
                insert into cmd_result(result) values (concat("no such command: ", substring_index(cmd,' ', 1)));
        end case;
END //
DELIMITER ;

-- ----------------------------
-- cd.sql
-- ----------------------------
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

-- ----------------------------
-- find.sql
-- ----------------------------
drop procedure if exists find;
delimiter //
create procedure find (
    in input varchar(255)
)
find_procedure:begin
	-- inout params
	declare directory varchar(255);
    declare filename varchar(255);

    -- use a file cursor to iterate through all matched files
    declare cursor_done int default false;
    declare matched_hash varchar(255) default null;
	declare temp_type varchar(1) default null;
    declare temp_owner varchar(255) default null;
    declare temp_group varchar(255) default null;
    declare temp_owner_read varchar(255) default null;
    declare temp_group_read varchar(255) default null;
    declare temp_others_read  varchar(255) default null;
	declare temp_owner_exec varchar(2) default '';
    declare temp_group_exec varchar(2) default '';
    declare temp_others_exec varchar(2) default '';
	declare tar_link varchar(255) default '';
	declare output_code int default 0;
	declare parsed_input varchar(255) default '';
    declare file_cursor cursor for
		-- recursively search all childs
		-- the result is a set with the parent and all its distinctive child
		with recursive cte (hash, name, parent, inode) as (
			select hash, name, parent, inode
			from tree
			where parent = directory
			union all
			select t.*
			from tree as t
			inner join cte
			on t.parent = cte.hash
		)
		select childs.hash, i.owner, i.group, i.owner_read_permission, i.group_read_permission, i.others_read_permission,
		       i.type, i.owner_exec_permission, i.group_exec_permission, i.others_exec_permission
        from (
			select * from cte
			union all select * from tree where hash = directory -- joins parent itself
			order by hash asc
		) as childs
		left join inodes i on childs.inode = i.inode
		where childs.name regexp filename; -- find childs with name matches file_name
    declare continue handler for not found set cursor_done = true;

    -- Use a temporary table to store all matched rows
    drop temporary table if exists cmd_result;
    create temporary table cmd_result
    (
        permission varchar(100) not null default '',
        n_link varchar(10) default '',
        owner varchar(50) default '',
        group_str varchar(50) default '',
        size_str varchar(10) default '',
        date_str varchar(20) default '',
        name_str varchar(100) default '',
        hash varchar(100) default ''
    );

    -- if --help option, output help
    if input = '--help' then
		insert into cmd_result(permission) values ("man find:");
        insert into cmd_result(permission) values ("find: accept the directory and (partial) name of the file being found.");
		insert into cmd_result(permission) values ("returns: output the “ls -l” results for all match.");
        insert into cmd_result(permission) values ("usage: find DIRECTORY FILENAME");
        leave find_procedure;
	end if;

    set @@sql_mode="NO_BACKSLASH_ESCAPES";
	# parse escaped space
	set parsed_input = replace(input,"\\ ", "<>");
    -- split input params
    set directory = replace(substring_index(parsed_input, ' ', 1),"<>", " ");
    set filename = replace(substring_index(parsed_input, ' ', -1),"<>", " ");

    set directory = parse_path(directory);
    if directory = '' then
		set directory = '/';
	end if;
	# directory error checking
    if (select count(*) from tree where tree.hash = directory) = 0 then
        insert into cmd_result(permission) values (concat("find: ", directory, ": No such file or directory"));
        set @@sql_mode=@@GLOBAL.SQL_MODE;
        leave find_procedure;
	end if;

    open file_cursor;
    parse_files: loop
		fetch file_cursor into matched_hash, temp_owner, temp_group, temp_owner_read, temp_group_read, temp_others_read, temp_type, temp_owner_exec, temp_group_exec, temp_others_exec;
        if cursor_done then
			leave parse_files;
		end if;
        if (
			(temp_owner = @current_user and temp_owner_read = 'r') or
			(temp_group = @current_user_group and temp_group_read = 'r') or
			(temp_others_read = 'r')
		) then
            if temp_type = '-' then
                # ls -l a file
                insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name_str)
                    select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size, from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name
                    from tree
                    inner join inodes on tree.inode = inodes.inode
                    inner join permission_str on inodes.inode = permission_str.inode
                    where tree.hash = matched_hash;
            elseif temp_type = 'd' then
                # ls -l a directory
                if (temp_owner = @current_user and temp_owner_exec = 'x') or
                   (temp_group = @current_user_group and temp_group_exec = 'x') or
                   (temp_others_exec = 'x') then
                    # the directory has execute permission
                    insert into cmd_result(permission) values(concat((select name from tree where hash = matched_hash), ":"));
                    # add total x for directory
                    insert ignore into cmd_result (permission) select concat("total: ", round(sum(size)/1000,0)) from tree inner join inodes where parent = matched_hash;

                    insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name_str, hash)
                        select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                               from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name, tree.hash
                        from tree
                        inner join inodes on tree.inode = inodes.inode
                        inner join permission_str on inodes.inode = permission_str.inode
                        where tree.parent = matched_hash;
                    update cmd_result
                    set name_str = concat(name_str, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where link = cmd_result.hash))
                    where name_str != '' and left(permission, 1) = 'l';
                else
                    # the directory does not has exec permission
                    insert into cmd_result(permission) values (concat("find: ", matched_hash, ": Permission Denied"));
                end if;
            elseif temp_type = 'l' then
                select symbolic_links.target from symbolic_links where link = matched_hash into tar_link;
                call ls_l_resolve_link(tar_link, output_code);
                if output_code = 0 then
                    # it links to a file
                    insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name_str)
                        select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                               from_unixtime(inodes.atime, "%b %d %H:%i"),
                               concat(tr.name, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where symbolic_links.link = matched_hash))
                        from tree as tr
                        inner join inodes on tr.inode = inodes.inode
                        inner join permission_str on inodes.inode = permission_str.inode
                        where tr.hash = matched_hash;

                elseif output_code = 1 then
                    # it do not have permission
                    insert into cmd_result(permission) values (concat("ls -l: ", matched_hash, ": Permission Denied"));
                elseif output_code = 2 then
                    # it links to a directory
                    insert into cmd_result(permission) values(concat((select name from tree where hash = matched_hash), ":"));
                    # add total x for directory
                    insert ignore into cmd_result (permission) select concat("total: ", round(sum(size)/1000,0)) from tree inner join inodes where parent = matched_hash;

                    insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name_str, hash)
                        select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                               from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name, tree.hash
                        from tree
                        inner join inodes on tree.inode = inodes.inode
                        inner join permission_str on inodes.inode = permission_str.inode
                        where tree.parent = matched_hash;
                    update cmd_result
                    set name_str = concat(name_str, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where link = cmd_result.hash))
                    where name_str != '' and left(permission, 1) = 'l' and (select parent from tree where tree.hash = cmd_result.hash) = matched_hash;

                end if;
            end if;

		else
            # user does not have read permission
            insert into cmd_result(permission) values (concat("find: ", matched_hash, ": Permission Denied"));
        end if;
	end loop;
    close file_cursor;
    alter table cmd_result drop column hash;
	set @@sql_mode=@@GLOBAL.SQL_MODE;
end//
DELIMITER ;

-- ----------------------------
-- grep.sql
-- ----------------------------
-- substring_list: returns all matched string within a text
drop procedure if exists substring_list;
delimiter //
create procedure substring_list(
	filename varchar(255),
    data text,
    pattern varchar(255),
    l_flag int
)
begin
    declare pattern_len int default CHAR_LENGTH(pattern);
    declare output_str text default '';
    declare occurence int default 1;
    declare line int default 1;
    declare line_content varchar(255) default '';
    line_match: while regexp_instr(data, '.*\n', 1, occurence) != 0 do
		set line_content = TRIM(TRAILING '\n' FROM convert(regexp_substr(data, '.*\n', 1, occurence) using 'utf8'));
		if regexp_instr(line_content, binary pattern, 1, 1) != 0 then
			if l_flag = 1 then
				insert into cmd_result values (filename);
				leave line_match;
			else
				insert into cmd_result select concat(filename, ": pos ", occurence, ": ", line_content);
			end if;
        end if;
        set occurence = occurence + 1;
    end while;
end//
delimiter ;

drop procedure if exists grep;
delimiter //
create procedure grep (
    in input varchar(255)
)
grep_procedure:begin
	-- input params
    declare pattern varchar(255) default '';
    declare filename varchar(255) default '';
    declare parent varchar(255) default '';
    declare l_flag int default 0;
    
	-- use a file cursor to iterate through all matched files
    declare cursor_done int default false;
    declare matched_file varchar(255) default null;
    declare matched_path varchar(255) default null;
    declare matched_data blob default null;
    declare temp_owner varchar(255) default null;
    declare temp_group varchar(255) default null;
    declare temp_owner_read varchar(255) default null;
    declare temp_group_read varchar(255) default null;
    declare temp_others_read  varchar(255) default null;
	declare file_cursor cursor for
		select t.hash, t.name, da.data, i.owner, i.group, 
				i.owner_read_permission, i.group_read_permission, i.others_read_permission from tree t
			left join inodes i on t.inode = i.inode
            left join symbolic_links s on s.link = t.hash
			left join data da on i.inode = da.inode or (select inode from tree where hash = s.target) = da.inode
			where t.hash regexp filename and t.parent = parse_path(@cd);
    declare continue handler for not found set cursor_done = true;
	
    -- Use a tempoary table to store all matched rows
    drop temporary table if exists cmd_result;
    create temporary table cmd_result (
		result varchar(100)
    );
    
    -- if --help option, output help
    if input = '--help' then
		insert into cmd_result(result) values (convert("man grep:" using 'utf8'));
        insert into cmd_result(result) values ("grep: accept the (partial) name of the file and seek the relevant pattern in the matching files.");
        insert into cmd_result(result) values ("returns: returns the (partial) name of the file matching lines inside the file.");
        insert into cmd_result(result) values ("usage: grep [-l] PATTERN [FILENAME]");
        insert into cmd_result(result) values ("-l: returns filename only");
        leave grep_procedure;
	end if;
    
    -- split input params. if first param is '-l', we need to use it
    set pattern = substring_index(input, ' ', 1);
    if pattern = '-l' then
		set l_flag = 1;
        set pattern = substring_index(substring_index(input, ' ', 2), ' ', -1);
		set filename = substring_index(input, ' ', -1);
	else
		set filename = substring_index(input, ' ', -1);
	end if;
	
    set filename = replace(filename, '*', '.*');
    -- need to let regex to match full line
    set pattern = if(pattern like ".*%", pattern, concat(".*", pattern));
	set pattern = if(pattern like "%.*", pattern, concat(pattern, ".*"));

    open file_cursor;
    parse_files: loop
		fetch file_cursor into matched_path, matched_file, matched_data, 
				temp_owner, temp_group, temp_owner_read, temp_group_read, temp_others_read;
        if cursor_done then
			leave parse_files;
		end if;
        if (
			(temp_owner = @current_user and temp_owner_read = 'r') or
			(temp_group = @current_user_group and temp_group_read = 'r') or
			(temp_others_read = 'r')
		) then
			call substring_list(matched_file, matched_data, pattern, l_flag);
		else
            # user does not have read permission
            insert into cmd_result(result) values (concat("grep: ", matched_path, ": Permission Denied"));
        end if;
	end loop;
    close file_cursor;
	
end//
DELIMITER ;
-- ----------------------------
-- ls.sql
-- ----------------------------
DROP PROCEDURE IF EXISTS ls;
DELIMITER $$
CREATE PROCEDURE ls (
    IN input varchar(100))
ls_procedure: BEGIN
    declare option_str varchar(100) default '';
    declare temp_dir varchar(100) default '';
    declare target varchar(100) default '';
    declare rest varchar(100) default '';
    declare space_counter int default 0;
    declare number_of_space int default 0;
    declare temp_type varchar(5) default '';
    declare temp_owner_read varchar(2) default '';
    declare temp_group_read varchar(2) default '';
    declare temp_others_read varchar(2) default '';
    declare temp_owner varchar(255) default '';
    declare temp_group varchar(255) default '';
    declare tar_link varchar(100) default '';
    declare output_code int default 0;

    set @@sql_mode="NO_BACKSLASH_ESCAPES";

    drop temporary table if exists cmd_result;
    create temporary table cmd_result
    (
        result varchar(100) not null
    );
    if input = '--help' or input = '-h' then
        insert into cmd_result(result) values ("man ls");
        insert into cmd_result(result) values ("usage: ls [-l] [file ...]");
        insert into cmd_result(result) values ("use -l to display detailed information");
    elseif left(input, 1) = '-' then
        # ls with option
        set option_str = substring_index(input, ' ', 1);
        if option_str = '-l' then
            call ls_l(substring(input, 4));
        else
            insert into cmd_result(result) values (concat("cd: ", option_str, ": invalid option"));
        end if;
    else
        # normal ls, need read permission
        drop temporary table if exists cmd_result;
        create temporary table cmd_result
        (
            result varchar(100) not null
        );
        set number_of_space = length(replace(replace(input, "\\ ", "<>")," ", "__")) - length(input);
        set rest = input;
        set space_counter = 0;

        while space_counter <= number_of_space do
            set space_counter = space_counter + 1;
            # get the first input; Replace escaped space
            set target = replace(substring_index(replace(rest,"\\ ", "<>")," ", 1),"<>", " ");
            set rest = substring(rest, instr(replace(rest,"\\ ", "<>"), " ")+1);
            set temp_dir = parse_path(target);

            select inodes.type, inodes.owner_read_permission, inodes.group_read_permission, inodes.others_read_permission, inodes.owner, inodes.`group`
                from tree inner join inodes on tree.inode = inodes.inode
                where tree.hash = temp_dir
                into temp_type, temp_owner_read, temp_group_read, temp_others_read, temp_owner, temp_group;

            if temp_type = '' then
                insert into cmd_result(result) values (concat("ls: ", target, ": No such file or directory"));
            elseif temp_type = '-' then
                # ls a file
                if (temp_owner = @current_user and temp_owner_read = 'r') or
               (temp_group = @current_user_group and temp_group_read = 'r') or
               (temp_others_read = 'r') then
                    insert into cmd_result select name from tree where hash = temp_dir;
                else
                    insert into cmd_result(result) values (concat("ls: ", target, ": Permission Denied"));
                end if;
            elseif temp_type = 'd' then
                #ls a directory
                if (temp_owner = @current_user and temp_owner_read = 'r') or
                   (temp_group = @current_user_group and temp_group_read = 'r') or
                   (temp_others_read = 'r') then
                    # the directory has read permission
                    if number_of_space > 0 then
                        # multi-input
                        insert into cmd_result(result) values(concat((select name from tree where hash = temp_dir), ":"));
                    end if;
                    insert ignore into cmd_result select name from tree where parent = temp_dir;
                else
                    # the directory does not has read permission
                    insert into cmd_result(result) values (concat("ls: ", target, ": Permission Denied"));
                end if;
            elseif temp_type = 'l' then
                select symbolic_links.target from symbolic_links where link = temp_dir into tar_link;
                call ls_resolve_link(tar_link, output_code);
                if output_code = 0 then
                    # the target is a file
                    insert into cmd_result select name from tree where hash = temp_dir;
                elseif output_code = 1 then
                    # do not have permission
                    insert into cmd_result(result) values (concat("ls: ", target, ": Permission Denied"));
                elseif output_code = 2 then
                    # the target is a directory
                    if number_of_space > 0 then
                        # multi-input
                        insert into cmd_result(result) values(concat((select name from tree where hash = temp_dir), ":"));
                    end if;
                    insert ignore into cmd_result select name from tree where parent = temp_dir;
                end if;
            end if;
            if number_of_space > 0 and space_counter <= number_of_space then
                insert into cmd_result(result) values('');
            end if;
        end while;
    end if;
    set @@sql_mode=@@GLOBAL.SQL_MODE;
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS ls_l;
DELIMITER @@
CREATE PROCEDURE ls_l (
    IN input varchar(100))
ls_l_procedure: BEGIN
    declare temp_dir varchar(100) default '';
    declare target varchar(100) default '';
    declare rest varchar(100) default '';
    declare space_counter int default 0;
    declare number_of_space int default 0;
    declare temp_type varchar(5) default '';
    declare temp_owner_exec varchar(2) default '';
    declare temp_group_exec varchar(2) default '';
    declare temp_others_exec varchar(2) default '';
    declare temp_owner varchar(255) default '';
    declare temp_group varchar(255) default '';
    declare temp_owner_read varchar(2) default '';
    declare temp_group_read varchar(2) default '';
    declare temp_others_read varchar(2) default '';
    declare tar_link varchar(100) default '';
    declare output_code int default 0;

    drop temporary table if exists cmd_result;
    create temporary table cmd_result
    (
        permission varchar(100) not null default '',
        n_link varchar(10) default '',
        owner varchar(50) default '',
        group_str varchar(50) default '',
        size_str varchar(10) default '',
        date_str varchar(20) default '',
        name varchar(100) default '',
        hash varchar(100) default ''
    );

    set number_of_space = length(replace(replace(input, "\\ ", "<>")," ", "__")) - length(input);
    set rest = input;
    set space_counter = 0;
    while space_counter <= number_of_space do
        set space_counter = space_counter + 1;
        set target = replace(substring_index(replace(rest,"\\ ", "<>")," ", 1),"<>", " ");
        set rest = substring(rest, instr(replace(rest,"\\ ", "<>"), " ")+1);
        # parse input path to hash in tree table
        set temp_dir = parse_path(target);

        select inodes.type, inodes.owner_exec_permission, inodes.group_exec_permission, inodes.others_exec_permission,
               inodes.owner_read_permission, inodes.group_read_permission, inodes.others_read_permission, inodes.owner, inodes.`group`
            from tree inner join inodes on tree.inode = inodes.inode
            where tree.hash = temp_dir
            into temp_type, temp_owner_exec, temp_group_exec, temp_others_exec, temp_owner_read, temp_group_read, temp_others_read, temp_owner, temp_group;

        if temp_type = '' then
            insert into cmd_result(permission) values (concat("ls -l: ", target, ": No such file or directory"));
        elseif temp_type = '-' then
            # ls -l a file
            if (temp_owner = @current_user and temp_owner_read = 'r') or
               (temp_group = @current_user_group and temp_group_read = 'r') or
               (temp_others_read = 'r') then
                # the file has read permission
                insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name)
                    select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size, from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name
                    from tree
                    inner join inodes on tree.inode = inodes.inode
                    inner join permission_str on inodes.inode = permission_str.inode
                    where tree.hash = temp_dir;
            else
                insert into cmd_result(permission) values (concat("ls -l: ", target, ": Permission Denied"));
            end if;
        elseif temp_type = 'd' then
            # ls -l a directory
            if (temp_owner = @current_user and temp_owner_exec = 'x') or
               (temp_group = @current_user_group and temp_group_exec = 'x') or
               (temp_others_exec = 'x') then
                # the directory has execute permission
                if number_of_space > 0 then
                    # multi-input
                    insert into cmd_result(permission) values(concat((select name from tree where hash = temp_dir), ":"));
                end if;
                # add total x for directory
                insert ignore into cmd_result (permission) select concat("total: ", round(sum(size)/1000,0)) from tree inner join inodes where parent = temp_dir;

                insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name, hash)
                    select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                           from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name, tree.hash
                    from tree
                    inner join inodes on tree.inode = inodes.inode
                    inner join permission_str on inodes.inode = permission_str.inode
                    where tree.parent = temp_dir;
                update cmd_result
                set name = concat(name, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where link = cmd_result.hash))
                where name != '' and left(permission, 1) = 'l' and (select parent from tree where tree.hash = cmd_result.hash) = temp_dir;
            else
                # the directory does not has read permission
                insert into cmd_result(permission) values (concat("ls -l: ", target, ": Permission Denied"));
            end if;
        elseif temp_type = 'l' then
            select symbolic_links.target from symbolic_links where link = temp_dir into tar_link;
            call ls_l_resolve_link(tar_link, output_code);
            if output_code = 0 then
                # it links to a file
                insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name)
                    select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                           from_unixtime(inodes.atime, "%b %d %H:%i"),
                           concat(tree.name, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where link = temp_dir))
                    from tree
                    inner join inodes on tree.inode = inodes.inode
                    inner join permission_str on inodes.inode = permission_str.inode
                    where tree.hash = temp_dir;
            elseif output_code = 1 then
                # it do not have permission
                insert into cmd_result(permission) values (concat("ls -l: ", target, ": Permission Denied"));
            elseif output_code = 2 then
                # it links to a directory
                if number_of_space > 0 then
                    # multi-input
                    insert into cmd_result(permission) values(concat((select name from tree where hash = temp_dir), ":"));
                end if;
                # add total x for directory
                insert ignore into cmd_result (permission) select concat("total: ", round(sum(size)/1000,0)) from tree inner join inodes where parent = temp_dir;

                insert ignore into cmd_result (permission, n_link, owner, group_str, size_str, date_str, name, hash)
                    select permission_str.permission, inodes.nlinks, inodes.owner, inodes.`group`, inodes.size,
                           from_unixtime(inodes.atime, "%b %d %H:%i"), tree.name, tree.hash
                    from tree
                    inner join inodes on tree.inode = inodes.inode
                    inner join permission_str on inodes.inode = permission_str.inode
                    where tree.parent = temp_dir;
                update cmd_result
                set name = concat(name, " => ", (select tree.name from symbolic_links inner join tree on symbolic_links.target = tree.hash where link = cmd_result.hash))
                where name != '' and left(permission, 1) = 'l' and (select parent from tree where tree.hash = cmd_result.hash) = temp_dir;

            end if;
        end if;
        if number_of_space > 0 and space_counter <= number_of_space then
                insert into cmd_result(permission) values('');
        end if;
    end while;
    alter table cmd_result drop column hash;
END @@
DELIMITER ;

DROP PROCEDURE IF EXISTS ls_resolve_link;
DELIMITER $$
CREATE PROCEDURE ls_resolve_link (
    IN temp_dir varchar(100),
    OUT output_code int)
ls_link_procedure: BEGIN
    declare temp_type varchar(5) default '';
    declare temp_owner_read varchar(2) default '';
    declare temp_group_read varchar(2) default '';
    declare temp_others_read varchar(2) default '';
    declare temp_owner varchar(255) default '';
    declare temp_group varchar(255) default '';
    declare tar_link varchar(100) default '';

    select inodes.type, inodes.owner_read_permission, inodes.group_read_permission, inodes.others_read_permission, inodes.owner, inodes.`group`
        from tree inner join inodes on tree.inode = inodes.inode
        where tree.hash = temp_dir
        into temp_type, temp_owner_read, temp_group_read, temp_others_read, temp_owner, temp_group;

    if temp_type = '-' then
        # link target is a file
        if (temp_owner = @current_user and temp_owner_read = 'r') or
       (temp_group = @current_user_group and temp_group_read = 'r') or
       (temp_others_read = 'r') then
           # we have permission
            set output_code = 0;
        else
            # we do not have permision
            set output_code = 1;
        end if;
    elseif temp_type = 'd' then
        #link target is a directory
        if (temp_owner = @current_user and temp_owner_read = 'r') or
           (temp_group = @current_user_group and temp_group_read = 'r') or
           (temp_others_read = 'r') then
            # the directory has read permission
            set output_code = 2;
        else
            # the directory does not has read permission
            set output_code = 1;
        end if;
    elseif temp_type = 'l' then
        select symbolic_links.target from symbolic_links where link = temp_dir into tar_link;
        call ls_resolve_link(tar_link, output_code);
    end if;
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS ls_l_resolve_link;
DELIMITER $$
CREATE PROCEDURE ls_l_resolve_link (
    IN temp_dir varchar(100),
    OUT output_code int)
ls_l_link_procedure: BEGIN
    declare temp_type varchar(5) default '';
    declare temp_owner_read varchar(2) default '';
    declare temp_group_read varchar(2) default '';
    declare temp_others_read varchar(2) default '';
    declare temp_owner_exec varchar(2) default '';
    declare temp_group_exec varchar(2) default '';
    declare temp_others_exec varchar(2) default '';
    declare temp_owner varchar(255) default '';
    declare temp_group varchar(255) default '';
    declare tar_link varchar(100) default '';

    select inodes.type, inodes.owner_exec_permission, inodes.group_exec_permission, inodes.others_exec_permission,
           inodes.owner_read_permission, inodes.group_read_permission, inodes.others_read_permission, inodes.owner, inodes.`group`
        from tree inner join inodes on tree.inode = inodes.inode
        where tree.hash = temp_dir
        into temp_type, temp_owner_exec, temp_group_exec, temp_others_exec, temp_owner_read, temp_group_read, temp_others_read, temp_owner, temp_group;
    if temp_type = '-' then
        # ls -l a file
        if (temp_owner = @current_user and temp_owner_read = 'r') or
           (temp_group = @current_user_group and temp_group_read = 'r') or
           (temp_others_read = 'r') then
            # the file has read permission
            set output_code = 0;
        else
            set output_code = 1;
        end if;
    elseif temp_type = 'd' then
        # ls -l a directory
        if (temp_owner = @current_user and temp_owner_exec = 'x') or
           (temp_group = @current_user_group and temp_group_exec = 'x') or
           (temp_others_exec = 'x') then
            # the directory has execute permission
            set output_code = 2;
        else
            # the directory does not has read permission
            set output_code = 1;
        end if;
    elseif temp_type = 'l' then
        select symbolic_links.target from symbolic_links where link = temp_dir into tar_link;
        call ls_l_resolve_link(tar_link,output_code);
    end if;
END $$
DELIMITER ;

-- ----------------------------
-- parse_path.sql
-- ----------------------------
DROP FUNCTION IF EXISTS parse_path;
DELIMITER @@
CREATE FUNCTION parse_path (path varchar(100))
    returns varchar(100) deterministic
parse_path_procedure: BEGIN
	declare temp_dir varchar(100) default '';
    declare slash_counter int default 0;
    declare number_of_slash int default 0;
    declare rest_path varchar(100) default '';
    declare target_path varchar(100) default '';
    declare path_cd varchar(100) default '';

    set number_of_slash = length(replace(path,"/", "__")) - length(path);
    set rest_path = path;
    set slash_counter = 0;
    set path_cd = @cd;

    path_loop: while slash_counter <= number_of_slash do
        set slash_counter = slash_counter + 1;
        set target_path = substring_index(rest_path, "/", 1);
        set rest_path = substring(rest_path, instr(rest_path, "/")+1);
        if path = '' then
            if @cd = '/' then
                set temp_dir = @cd;
            else
                set temp_dir = TRIM(TRAILING '/' FROM @cd);
            end if;
            leave path_loop;
        elseif left(path, 1) = '~' and slash_counter = 1 then
            set temp_dir = TRIM(TRAILING '/' FROM @user_dir);
            if rest_path = '' then
                leave path_loop;
            end if;
            set path_cd = @user_dir;
            iterate path_loop;
        elseif path = '/' then
            set temp_dir = '/';
            leave path_loop;
        elseif left(path, 1) = '/' then
            set temp_dir = TRIM(TRAILING '/' FROM path);
            leave path_loop;
        end if;

        if target_path = '.' then
            if path_cd = '/' then
                set temp_dir = path_cd;
            else
                set temp_dir = TRIM(TRAILING '/' FROM path_cd);
            end if;
        elseif target_path = '..' then
            if path_cd = @root_dir then
                # cd is at root
                set temp_dir = path_cd;
            else
                set temp_dir = (select parent from tree where hash = TRIM(TRAILING '/' FROM path_cd));
                if temp_dir = '' or temp_dir is null then
                    # the parent does not exist
                    set temp_dir = path;
                    leave path_loop;
                end if;
                set path_cd = concat(temp_dir, '/');
            end if;
        else
            set temp_dir = concat(path_cd, target_path);
            set path_cd = concat(path_cd, target_path,'/');
        end if;
        if rest_path = '' then
            leave path_loop;
        end if;
    end while;
	return temp_dir;
END @@
DELIMITER ;
