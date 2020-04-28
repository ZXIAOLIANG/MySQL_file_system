use ece356_unix_fs;

create index parent_index on tree (parent);
create index link_index on symbolic_links (link);
create index target_index on symbolic_links (target);