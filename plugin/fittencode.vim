" plugin name: Fitten Code vim
" plugin version: 0.2.1

if exists("g:loaded_fittencode")
    finish
  endif
let g:loaded_fittencode = 1

let s:hlgroup = 'FittenSuggestion'
function! SetSuggestionStyle() abort
    if &t_Co == 256
        hi def FittenSuggestion guifg=#808080 ctermfg=244
    else
        hi def FittenSuggestion guifg=#808080 ctermfg=8
    endif
    call prop_type_add(s:hlgroup, {'highlight': s:hlgroup})
endfunction

function! Fittenlogin(account, password)
    let l:login_url = 'https://fc.fittenlab.cn/codeuser/login'
    let l:json_data = '{"username": "' . a:account . '", "password": "' . a:password . '"}'
    let l:login_command = 'curl -s -X POST -H "Content-Type: application/json" -d ' . shellescape(l:json_data) . ' ' . l:login_url
    let l:response = system(l:login_command)
    let l:login_data = json_decode(l:response)

    if v:shell_error || !has_key(l:login_data, 'code') || l:login_data.code != 200
        echo "Login failed"
        return
    endif

    let l:user_token = l:login_data.data.token

    let l:fico_url = 'https://fc.fittenlab.cn/codeuser/get_ft_token'
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

function! ClearCompletion()
    unlet! b:fitten_suggestion
    call prop_remove({'type': s:hlgroup, 'all': v:true})
endfunction

function! ClearCompletionByCursorMoved()
    if col('.') != col('$')
        call ClearCompletion()
    endif
endfunction

function! CodeCompletion()
    call ClearCompletion()

    let l:filename = substitute(expand('%'), '\\', '/', 'g')

    let l:file_content = join(getline(1, '$'), "\n")
    let l:line_num = line('.')
    if getcurpos()[2] == getcurpos()[4]
        let l:col_num = getcurpos()[2]
    else
        let l:col_num = getcurpos()[2] + 1
    endif
    
    let l:prefix = join(getline(1, l:line_num - 1), '\n')
    if !empty(l:prefix)
        let l:prefix = l:prefix . '\n'
    endif
    let l:prefix = l:prefix . strpart(getline(l:line_num), 0, l:col_num - 1)
    
    let l:suffix = strpart(getline(l:line_num), l:col_num - 1)
    if l:line_num < line('$')
        let l:suffix = l:suffix . '\n' . join(getline(l:line_num + 1, '$'), '\n')
    endif

    let l:prompt = "!FCPREFIX!" . l:prefix . "!FCSUFFIX!" . l:suffix . "!FCMIDDLE!"
    let l:escaped_prompt = escape(l:prompt, '\"')
    " replace \\n to \n
    let l:escaped_prompt = substitute(l:escaped_prompt, '\\\\n', '\\n', 'g')
    " replace \\t to \t
    let l:escaped_prompt = substitute(l:escaped_prompt, '\t', '\\t', 'g')
    let l:token = join(readfile($HOME . '/.vimapikey'), "\n")

    let l:params = '{"inputs": "' . l:escaped_prompt . '", "meta_datas": {"filename": "' . l:filename . '"}}'
    
    let l:tempfile = tempname()
    call writefile([l:params], l:tempfile)

    let l:server_addr = 'https://fc.fittenlab.cn/codeapi/completion/generate_one_stage/'

    let l:cmd = 'curl -s -X POST -H "Content-Type: application/json" -d @' . l:tempfile . ' "' . l:server_addr . l:token . '?ide=vim&v=0.2.1"'
    let l:response = system(l:cmd)

    call delete(l:tempfile)

    if v:shell_error
        echow "Request failed"
        return
    endif
    let l:completion_data = json_decode(l:response)

    if !has_key(l:completion_data, 'generated_text')
        return
    endif

    let l:generated_text = l:completion_data.generated_text
    let l:generated_text = substitute(l:generated_text, '<.endoftext.>', '', 'g')

    if empty(l:generated_text)
        echow "Fitten Code: No More Suggestions"
        call timer_start(2000, {-> execute('echo ""')})
        return
    endif

    let l:text = split(l:generated_text, "\n", 1)
    if empty(l:text[-1])
        call remove(l:text, -1)
    endif

    let l:is_first_line = v:true
    for line in text
        if empty(line)
            let line = " "
        endif
        if l:is_first_line is v:true
            let l:is_first_line = v:false
            call prop_add(line('.'), l:col_num, {'type': s:hlgroup, 'text': line})
        else
            call prop_add(line('.'), 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
        endif
    endfor

    let b:fitten_suggestion = l:generated_text
endfunction

function! FittenAcceptMain()
    echo "Accept"
    let default = pumvisible() ? "\<C-N>" : "\t"

    if mode() !~# '^[iR]' || !exists('b:fitten_suggestion')
        return g:fitten_accept_key == "\t" ? default : g:fitten_accept_key
    endif

    let l:text = b:fitten_suggestion

    call ClearCompletion()

    return l:text
endfunction

function! FittenInsert(text, is_first_line) abort
    if a:is_first_line == v:false
        call append('.', '')
        let l:line = line('.') + 1
    else
        let l:line = line('.')
    endif
    let l:col = col('.')
    let l:oldline = getline(l:line)
    let l:newline = l:oldline[:l:col-2] . a:text . l:oldline[l:col-1:]
    call setline(l:line, l:newline)
    call cursor(l:line, l:col + len(a:text))
endfunction

function FittenAccept()
    let l:accept = FittenAcceptMain()
    let l:accept_lines = split(l:accept, "\n", v:true)

    let l:is_first_line = v:true
    for line in l:accept_lines
        call FittenInsert(line, l:is_first_line)
        let l:is_first_line = v:false
    endfor
endfunction

function! FittenAcceptable()
    return (mode() !~# '^[iR]' || !exists('b:fitten_suggestion')) ? 0 : 1
endfunction

if !exists('g:fitten_trigger')
    let g:fitten_trigger = "\<C-l>"
endif
if !exists('g:fitten_accept_key')
    let g:fitten_accept_key = "\<Tab>"
endif
function! FittenMapping()
    execute "inoremap" keytrans(g:fitten_trigger) '<Cmd>call CodeCompletion()<CR>'
    if g:fitten_accept_key isnot v:none
        execute 'inoremap' keytrans(g:fitten_accept_key) '<Cmd>call FittenAccept()<CR>'
    endif
endfunction

augroup fittencode
    autocmd!
    autocmd CursorMovedI * call ClearCompletionByCursorMoved()
    autocmd InsertLeave  * call ClearCompletion()
    autocmd BufLeave     * call ClearCompletion()
    autocmd ColorScheme,VimEnter * call SetSuggestionStyle()
    " Map tab using vim enter so it occurs after all other sourcing.
    autocmd VimEnter             * call FittenMapping()
augroup END

