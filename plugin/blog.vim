" Copyright (C) 2007 Adrien Friggeri.
"
" This program is free software; you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation; either version 2, or (at your option)
" any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program; if not, write to the Free Software Foundation,
" Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  
" 
" Maintainer:	Adrien Friggeri <adrien@friggeri.net>
"               Pigeond <http://pigeond.net/blog/>
"               BOYPT <pentie@gmail.com>
"               Justin Sattery <justin.slattery@fzysqr.com>
"
" URL:		http://www.friggeri.net/projets/vimblog/
"           http://pigeond.net/blog/2009/05/07/vimpress-again/
"           http://pigeond.net/git/?p=vimpress.git
"           http://apt-blog.net
"           http://fzysqr.com/
"
" Version:	1.0.01
" Last Change:  2010 August 20 - Fixed a bug with BlogSave command, and added 
" feature to take an existing document and use the BlogNew command to 
" convert it to a blog post (which can be saved with the header intact). 
"
"#######################################################################

if !has("python")
    finish
endif

function! CompletionSave(ArgLead, CmdLine, CursorPos)
  return "publish\ndraft\n"
endfunction

command! -nargs=0 BlogNew exec('py blog_new_post()')
command! -nargs=? BlogList exec('py blog_list_posts(<f-args>)')
command! -nargs=? -complete=custom,CompletionSave BlogSave exec('py blog_send_post(<f-args>)')
command! -nargs=1 BlogOpen exec('py blog_open_post(<f-args>)')
command! -nargs=1 -complete=file BlogUpload exec('py blog_upload_media(<f-args>)')
command! -nargs=0 BlogCode exec('py blog_append_code()')

"#####################
"#      Settings     #
"#####################

if !exists("g:blog_username")
    let g:blog_username = 'username'
endif
if !exists("g:blog_password")
    let g:blog_password = 'password'
endif
if !exists("g:blog_url")
    let g:blog_url = 'http://yourblog.com/xmlrpc.php'
endif

python <<EOF
# -*- coding: utf-8 -*-
import urllib , urllib2 , vim , xml.dom.minidom , xmlrpclib , sys , string , re, os, mimetypes

#Remap to python variables

blog_username = vim.eval("g:blog_username")
blog_password = vim.eval("g:blog_password")
blog_url = vim.eval("g:blog_url")

image_template = '<img title="%(file)s" src="%(url)s" class="aligncenter" />'
#####################
# Do not edit below #
#####################

handler = xmlrpclib.ServerProxy(blog_url).metaWeblog

def __exception_check(func):
    def __check(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except xmlrpclib.Fault, e:
            sys.stderr.write("xmlrpc error: %s" % e.faultString.encode("utf-8"))
        except xmlrpclib.ProtocolError, e:
            sys.stderr.write("xmlrpc error: %s %s" % (e.url, e.errmsg))
        except IOError, e:
            sys.stderr.write("network error: %s" % e)

    return __check

@__exception_check
def blog_send_post(pub = "draft"):

    if pub == "publish":
        publish = True
    elif pub == "draft":
        publish = False
    else:
        sys.stderr.write(":BlogSave draft|publish")
        return

    def get_line(what):
        start = 0
        while not vim.current.buffer[start].startswith('"'+what):
            start +=1
        return start

    def get_meta(what): 
        start = get_line(what)
        end = start + 1
        while not vim.current.buffer[end][0] == '"':
            end +=1
        return " ".join(vim.current.buffer[start:end]).split(":")[1].strip()
        
    strid = get_meta("StrID")
    title = get_meta("Title")
    slug = get_meta("Slug").replace(" ", "-")
    cats = [i.strip() for i in get_meta("Cats").split(",")]
    tags = get_meta("Tags")
  
    text_start = 0
    while not vim.current.buffer[text_start] == "\"========== Content ==========":
        text_start +=1
    text = '\n'.join(vim.current.buffer[text_start + 1:])

    post = dict(title = title, description = text,
            categories = cats, mt_keywords = tags,
            wp_slug = slug)

    if strid == '':
        strid = handler.newPost('', blog_username,
            blog_password, post, publish)
        vim.current.buffer[get_line("StrID")] = "\"StrID : %s" % strid
        notify = "Blog %s.   ID=%s" % ("Published" if publish else "Saved", strid)
    else:
        handler.editPost(strid, blog_username,
            blog_password, post, publish)
        notify = "Blog Edited. %s.   ID=%s" %  ("Published" if publish else "Saved", strid)

    sys.stdout.write(notify)
    vim.command('set nomodified')


@__exception_check
def blog_new_post():

    def blog_get_cats():
        l = handler.getCategories('', blog_username, blog_password)
        return ", ".join([i["description"].encode("utf-8") for i in l])

    currentContent = vim.current.buffer[:]
    del vim.current.buffer[:]
    vim.command("set modifiable")
    vim.command("set syntax=blogsyntax")

    vim.current.buffer[0] = "\"=========== Meta ============"
    vim.current.buffer.append("\"StrID : ")
    vim.current.buffer.append("\"Title : ")
    vim.current.buffer.append("\"Slug  : ")
    vim.current.buffer.append("\"Cats  : %s" % blog_get_cats())
    vim.current.buffer.append("\"Tags  : ")
    vim.current.buffer.append("\"========== Content ==========")
    vim.current.buffer.append("")

    vim.current.buffer.append(currentContent)

    vim.current.window.cursor = (len(vim.current.buffer), 0)
    vim.command('set nomodified')
    vim.command('set textwidth=0')

@__exception_check
def blog_open_post(post_id):
    post = handler.getPost(post_id, blog_username, blog_password)
    vim.command("set modifiable")
    vim.command("set syntax=blogsyntax")

    del vim.current.buffer[:]
    vim.current.buffer[0] =   "\"=========== Meta ============"
    vim.current.buffer.append("\"StrID : "+str(post_id))
    vim.current.buffer.append("\"Title : "+(post["title"]).encode("utf-8"))
    vim.current.buffer.append("\"Slug  : "+(post["wp_slug"]).encode("utf-8"))
    vim.current.buffer.append("\"Cats  : "+",".join(post["categories"]).encode("utf-8"))
    vim.current.buffer.append("\"Tags  : "+(post["mt_keywords"]).encode("utf-8"))
    vim.current.buffer.append("\"========== Content ==========")

    content = (post["description"]).encode("utf-8")
    for line in content.split('\n'):
        vim.current.buffer.append(line)
    text_start = 0

    while not vim.current.buffer[text_start] == "\"========== Content ==========":
        text_start +=1
    text_start +=1

    vim.current.window.cursor = (text_start+1, 0)
    vim.command('set nomodified')
    vim.command('set textwidth=0')

    if vim.eval("mapcheck('<enter>')"):
        vim.command('unmap <enter>')

def blog_list_edit():
    row = vim.current.window.cursor[0]
    id = vim.current.buffer[row - 1].split()[0]
    blog_open_post(int(id))

@__exception_check
def blog_list_posts(count = "30"):
    allposts = handler.getRecentPosts('',blog_username, 
            blog_password, int(count))

    del vim.current.buffer[:]
    vim.command("set syntax=blogsyntax")
    vim.current.buffer[0] = "\"====== List of Posts ========="

    for p in allposts:
        title = u"%(postid)s\t%(title)s" % p
        vim.current.buffer.append(title.encode('utf8'))

    vim.command('set nomodified')
    vim.command("set nomodifiable")
    vim.current.window.cursor = (2, 0)
    if not vim.eval("mapcheck('<enter>')"):
        vim.command('map <enter> :py blog_list_edit()<cr>')

@__exception_check
def blog_upload_media(file_path):
    if not os.path.exists(file_path):
        sys.stderr.write("File does not exist: %s" % file_path)
        return

    name = os.path.basename(file_path)
    filetype = mimetypes.guess_type(file_path)[0]
    with open(file_path, 'r') as f:
        bits = xmlrpclib.Binary(f.read())

    result = handler.newMediaObject(1, blog_username, blog_password, 
            dict(name = name, type = filetype, bits = bits))

    ran = vim.current.range

    if filetype.startswith("image"):
        img = image_template % result
        ran.append(img)
    else:
        ran.append(result["url"])
    ran.append('')

def blog_append_code():
    ran = vim.current.range
    ran.append('<pre lang="" line="1" escaped="True">')
    ran.append('</pre>')



