# Fitten Code Vim

Fitten Code AI Programming Assistant Vim Edition, helps you to use AI for automatic completion in vim, with support for functions like login, logout, shortcut key completion, and single file plugin, convenient for integration into your environment.

Fitten Code AI编程助手 Vim 版本，帮助您在vim中通过AI进行自动补全，支持功能：登录、登出、快捷键补全，单文件插件，方便集成到您的环境当中。

![img](./vim.gif)

## Install

```bash

# github install
mkdir -p ~/.vim/plugin
curl -o ~/.vim/plugin/fittencode.vim https://raw.githubusercontent.com/fittentech/fittencode.vim/master/fittencode.vim

# gitee install 
mkdir -p ~/.vim/plugin
curl -o ~/.vim/plugin/fittencode.vim https://gitee.com/fittentech/fittentech.vim/raw/master/fittencode.vim

```

## Usage

If you haven't registered yet, please click [here](https://codewebchat.fittentech.cn:15443?ide=vim) to register.

After registration, enter `:Fittenlogin <username> <passwd>` in vim command line to login. After successful login, press `<C-L>` to toggle completion and `<TAB>` to accept the completion. You can also modify the shortcut key binding in the fittencode.vim file to your preferred completion shortcut.

如果您还没注册，请先点击[这里](https://codewebchat.fittentech.cn:15443?ide=vim)注册。

注册完成后，在vim命令行输入`:Fittenlogin <username> <passwd>`登录；登录成功后，按下`<C-L>`即可弹出补全提示，按下 `<TAB>` 键完成补全，您也可以修改`fittencode.vim`文件的快捷键绑定，改为自己习惯的补全快捷键。

```python
# Intelligent completion example for input code
def calculate_area(radius):
    return 3.14 * radius ** 2

# Intelligent prompt example when the cursor is on the function name and the shortcut key is pressed
calculate_area(|)
```

You can also enter `:Fittenlogout` to log out.

您还可以输入`:Fittenlogout`登出。
