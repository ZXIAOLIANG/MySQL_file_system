-- use testenv;

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

set @current_user = 'd5lei';
set @current_user_group = 'uw';
set @cd = '/Users/d5lei';
call grep('this *.txt');
select * from cmd_result;
