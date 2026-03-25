" plugin name: Fitten Code vim
" plugin version: 0.2.1

if exists("g:loaded_fittencode")
    finish
  endif
let g:loaded_fittencode = 1
let g:accept_just_now = 0

let s:hlgroup = 'FittenSuggestion'
let s:virtual_text_line = 0
let s:virtual_text_start_col = 0
let s:virtual_text_updated = 0
function! SetSuggestionStyle() abort
    if &t_Co == 256
        hi FittenSuggestion guifg=#808080 ctermfg=244
    else
        hi FittenSuggestion guifg=#808080 ctermfg=8
    endif
    if empty(prop_type_get(s:hlgroup))
        call prop_type_add(s:hlgroup, {'highlight': s:hlgroup})
    endif
endfunction

let g:fitten_auto_completion = 0

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
    let g:fitten_login_status = 1
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
"        echo "Logged in"
        return 1
    else
"        echo "Not logged in"
        return 0
    endif
endfunction

function! ClearCompletion(clear_state=1)
    call prop_remove({'type': s:hlgroup, 'all': v:true})
    if a:clear_state == 1
        if exists('b:fitten_suggestion')
            unlet! b:fitten_suggestion
        endif
        if exists('s:job') && job_status(s:job) == 'run'
            call job_stop(s:job)
            unlet! s:job
        endif
        let s:virtual_text_line = 0
        let s:virtual_text_start_col = 0
    endif
endfunction

function! ClearCompletionByCursorMoved()
    if exists('g:accept_just_now') && g:accept_just_now == 2
        let g:accept_just_now = 1
    endif
    if exists('b:fitten_suggestion') && !s:virtual_text_updated
        call ClearCompletion(0)
    endif
endfunction

function! CodeCompletion()
    if exists('b:fitten_suggestion') && s:virtual_text_line == line('.')
        return
    endif
    call ClearCompletion()

    let l:filename = substitute(expand('%'), '\\', '/', 'g')

    let l:file_content = join(getline(1, '$'), "\n")
    let l:line_num = line('.')
    let l:col_num = getcurpos()[2]

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
    "let l:response = system(l:cmd)

    let result = []
    let s:job = job_start(l:cmd, {
                \ 'out_mode': 'raw',
                \ 'out_cb': { channel, data -> add(result, data) },
                \ 'exit_cb': { job, status -> s:OnExit(result, status, tempfile, col_num) }
                \ })

endfunction

fu s:OnExit(out, status, tempfile, col_num) abort
    call delete(a:tempfile)
    if a:status != 0
        return
    endif

    let l:completion_data = json_decode(join(a:out, "\n"))

    if !has_key(l:completion_data, 'generated_text')
        return
    endif

    let l:generated_text = l:completion_data.generated_text
    let l:generated_text = substitute(l:generated_text, '<.endoftext.>', '', 'g')

    if empty(l:generated_text)
        echow "Fitten Code: No More Suggestions"
        call timer_start(1500, {-> execute('echo ""')})
        return
    endif

    let l:text = split(l:generated_text, "\n", 1)
    if empty(l:text[-1])
        call remove(l:text, -1)
    endif
    let l:text = map(l:text, 'substitute(v:val, "\t", repeat(" ", &ts), "g")')

    let b:fitten_suggestion = l:generated_text
    let s:virtual_text_updated = 0
    let s:virtual_text_line = line('.')
    let s:virtual_text_start_col = a:col_num

    if a:col_num != getcurpos()[2]
		call s:UpdateVirtualTextOnInput()
		return
	endif

    let l:is_first_line = v:true
    for line in text
        if empty(line)
            let line = " "
        endif
        if l:is_first_line is v:true
            let l:is_first_line = v:false
            call prop_add(line('.'), a:col_num, {'type': s:hlgroup, 'text': line})
        else
            call prop_add(line('.'), 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
        endif
    endfor
endf

function! s:UpdateVirtualTextOnInput() abort
    if !exists('b:fitten_suggestion') 
        \ || s:virtual_text_line != line('.')
        return 0
    endif
    if s:virtual_text_start_col > getcurpos()[2]
        call ClearCompletion()
        return 0
    endif
    let l:cur_col = getcurpos()[2]
    let l:line_content = getline('.')
    let l:input_content = strpart(l:line_content, s:virtual_text_start_col - 1, l:cur_col - s:virtual_text_start_col)
    let l:input_len = len(l:input_content)

    if l:input_len == 0
        return 0
    endif
    let l:virtual_prefix = strpart(b:fitten_suggestion, 0, l:input_len)
    if l:virtual_prefix !=? l:input_content
        call ClearCompletion()
        return 0
    endif
    let l:remaining_text = strpart(b:fitten_suggestion, l:input_len)
    if empty(l:remaining_text)
        call ClearCompletion()
        return 1
    endif
    call ClearCompletion(0)
    let l:text_lines = split(l:remaining_text, "\n", 1)
    if empty(l:text_lines[-1])
        call remove(l:text_lines, -1)
    endif
    let l:text_lines = map(l:text_lines, 'substitute(v:val, "\t", repeat(" ", &ts), "g")')
    let l:is_first_line = v:true
    for line in l:text_lines
        if empty(line)
            let line = " "
        endif
        if l:is_first_line
            let l:is_first_line = v:false
            call prop_add(line('.'), l:cur_col, {'type': s:hlgroup, 'text': line})
        else
            call prop_add(line('.'), 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
        endif
    endfor
    let b:fitten_suggestion = l:remaining_text
    let s:virtual_text_updated = 1
    let s:virtual_text_start_col = l:cur_col
    return 1
endfunction

function! CodeAutoCompletion()
    if g:fitten_login_status == 0
        return ""
    endif
    if !exists('g:accept_just_now') || g:accept_just_now == 1 || g:accept_just_now == 2
        let g:accept_just_now = g:accept_just_now - 1
        return ""
    endif
    if col('.') == col('$')
        call CodeCompletion()
        return ""
    endif
    if empty(substitute(getline('.')[col('.') - 1:], '\s', '', 'g'))
        call CodeCompletion()
        return ""
    endif
endfunction

function! FittenAcceptMain()
    echo "Accept"

    if mode() !~# '^[iR]' || !exists('b:fitten_suggestion')
        return ''
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
    let l:prefix = strpart(l:oldline, 0, l:col-1)
    let l:suffix = strpart(l:oldline, l:col-1)
    let l:newline = l:prefix . a:text . l:suffix
    call setline(l:line, l:newline)
    call cursor(l:line, l:col + len(a:text))
endfunction

function FittenAccept()
    let g:accept_just_now = 2

    let l:accept = FittenAcceptMain()
    if empty(l:accept)
        let l:feed = pumvisible() ? "\<C-N>" : "\<Tab>"
        let l:feed = g:fitten_accept_key == '\t' ? l:feed : g:fitten_accept_key
        call feedkeys(l:feed, 'n')
        return
    endif

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
if !exists('g:fitten_login_status')
    let g:fitten_login_status = CheckLoginStatus()
endif
function! FittenMapping()
    execute "inoremap" keytrans(g:fitten_trigger) '<Cmd>call CodeCompletion()<CR>'
    if g:fitten_accept_key isnot v:none
        execute 'inoremap' keytrans(g:fitten_accept_key) '<Cmd>call FittenAccept()<CR>'
    endif
endfunction

command! FittenAutoCompletionOn let g:fitten_auto_completion = 1 | echo 'Fitten Code Auto Completion Enabled'

command! FittenAutoCompletionOff let g:fitten_auto_completion = 0 | echo 'Fitten Code Auto Completion Disabled'

augroup fittencode
    autocmd!
    autocmd CursorMovedI * call ClearCompletionByCursorMoved()
    autocmd InsertLeave  * call ClearCompletion()
    autocmd BufLeave     * call ClearCompletion()
    autocmd ColorScheme,VimEnter * call SetSuggestionStyle()
    " Map tab using vim enter so it occurs after all other sourcing.
    autocmd VimEnter             * call FittenMapping()
    set updatetime=1500
    autocmd CursorHoldI  * if g:fitten_auto_completion == 1 | call CodeAutoCompletion() | endif
    autocmd TextChangedI * call s:UpdateVirtualTextOnInput()
augroup END
