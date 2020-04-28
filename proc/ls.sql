-- use ece356_unix_fs;

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
