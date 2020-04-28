-- use ece356_unix_fs;

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
