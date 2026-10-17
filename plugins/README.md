# Plugins for Lotus

Plugins add commands, tools for the AI and start screen lines to Lotus. How to build one: [PLUGINS.md](../PLUGINS.md).

## The examples here

| Plugin | Access | What it shows |
|---|---|---|
| [todo](todo/) | limited | A command (`lotus todo`), three AI tools (add, list, done) and a start screen line; its list lives in its data folder |
| [github](github/) | limited, with the internet | A plugin in Python: stars, forks and the newest release of a repository, and GitHub's zen on the start screen |
| [hello](hello/) | full | Lotus' own functions and settings – the look of `ui_*`, the theme, the features that are on |

Install one straight from GitHub – or all three at once with the [examples pack](../packs/examples/pack.conf):

```
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/todo
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#packs/examples
```

or drag their folders from a copy of this repository into `lotus plugin installer`.

## Plugins made by others

None yet – yours could be the first. Put your plugin in its own git repository (the `plugin.conf` at the top),
then open a pull request that adds a line here:

| Plugin | By | Access | What it does |
|---|---|---|---|
| | | | |

Several plugins that belong together – with the settings that make them work – can be shared as one
[plugin pack](../PLUGINS.md#plugin-packs): a repository with a `pack.conf`. `lotus plugin pack <name>` makes one from
your plugins.

Lotus shows anyone who installs it what the plugin brings and may do. Plugins with full access run with the rights
of whoever installs them – say in your README why yours needs it.
