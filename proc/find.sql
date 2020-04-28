-- use testenv;

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
