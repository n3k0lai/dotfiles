# Terminal greeting
set fish_greeting (fortune);

# Prompt aesthetics
function fish_prompt
  echo -n (prompt_pwd);
  set_color 6dba09;
  echo -n " ~";
  set_color a292ff;
  echo -n "> ";
end

#make sure su uses fish
function su
  /bin/su --shell=/usr/bin/fish $argv
end