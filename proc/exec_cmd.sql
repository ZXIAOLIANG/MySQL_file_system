-- use ece356_unix_fs;

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
