" plugin name: Fitten Code vim
" plugin version: 0.1.0 

if exists("g:loaded_fittencode")
  finish
endif
let g:loaded_fittencode = 1

function! Fittenlogin(lgstring, password2)
    let l:login_url = 'https://codeuser.fittentech.cn:14443/login'
    let l:json_data = '{"username": "' . a:lgstring . '", "password": "' . a:password2 . '"}'
    let l:login_command = 'curl -s -X POST -H "Content-Type: application/json" -d ' . shellescape(l:json_data) . ' ' . l:login_url
    let l:response = system(l:login_command)
    let l:login_data = json_decode(l:response)

    if v:shell_error || !has_key(l:login_data, 'code') || l:login_data.code != 200
        echo "Login failed"
        return
    endif

    let l:user_token = l:login_data.data.token

    let l:fico_url = 'https://codeuser.fittentech.cn:14443/get_ft_token'
    let l:fico_command = 'curl -s -H "Authorization: Bearer ' . l:user_token . '" ' . l:fico_url
    let l:fico_response = system(l:fico_command)
    let l:fico_data = json_decode(l:fico_response)

    if v:shell_error || !has_key(l:fico_data, 'data')
        echo "Login failed"
        return
    endif

    let l:apikey = l:fico_data.data.fico_token
    call writefile([l:apikey], $HOME . '/.vimapikey')

    echo "Login successful, API key saved"
endfunction

command! -nargs=+ Fittenlogin call Fittenlogin(<f-args>)

function! Fittenlogout()
    if filereadable($HOME . '/.vimapikey')
        call delete($HOME . '/.vimapikey')
        echo "Logged out successfully"
    else
        echo "You are already logged out"
    endif
endfunction

command! Fittenlogout call Fittenlogout()


function! CheckLoginStatus()
    if filereadable($HOME . '/.vimapikey')
        echo "Logged in"
    else
        echo "Not logged in"
    endif
endfunction

function! CodeCompletion()
    let l:filename = expand('%')

    let l:file_content = join(getline(1, '$'), "\n")
    let l:line_num = line('.')
    let l:col_num = col('.')

    let l:prefix = join(getline(1, l:line_num - 1), '\n') . '\n' . strpart(getline(l:line_num), 0, l:col_num)
    
    let l:suffix = strpart(getline(l:line_num), l:col_num) . '\n' . join(getline(l:line_num + 1, '$'), '\n')

    let l:prompt = "!FCPREFIX!" . l:prefix . "!FCSUFFIX!" . l:suffix . "!FCMIDDLE!"
    let l:escaped_prompt = escape(l:prompt, '\"')
    " replace \\n to \n
    let l:escaped_prompt = substitute(l:escaped_prompt, '\\\\n', '\\n', 'g')
    let l:token = join(readfile($HOME . '/.vimapikey'), "\n")

    let l:params = '{"inputs": "' . l:escaped_prompt . '", "meta_datas": {"filename": "' . l:filename . '"}}'
    
    let l:tempfile = tempname()
    call writefile([l:params], l:tempfile)

    let l:server_addr = 'https://codeapi.fittentech.cn:13443/generate_one_stage/'

    let l:cmd = 'curl -s -X POST -H "Content-Type: application/json" -d @' . l:tempfile . ' "' . l:server_addr . l:token . '?ide=vim&v=0.1.0"'
    let l:response = system(l:cmd)
    " echo l:cmd

    if v:shell_error
        echo "Request failed"
        " echo l:cmd
        return
    endif
    let l:completion_data = json_decode(l:response)

    call delete(l:tempfile)

    " TODO: 显示代码补全建议和用户交互
    " echo l:completion_data

    " get generated_text from completion_data
    let l:generated_text = l:completion_data.generated_text

    " replace <|endoftext|> to empty
    let l:generated_text = substitute(l:generated_text, '<.endoftext.>', '', 'g')
    " echo l:generated_text
    
    " echo l:generated_text

    let l:save_ai = &autoindent
    let l:save_cin = &cindent
    let l:save_si = &smartindent
    let l:save_paste = &paste

    set noautoindent nocindent nosmartindent paste

    execute "normal! a" . l:generated_text
    
    let &autoindent = l:save_ai
    let &cindent = l:save_cin
    let &smartindent = l:save_si
    let &paste = l:save_paste
endfunction

inoremap <C-l> <C-O>:call CodeCompletion()<CR>