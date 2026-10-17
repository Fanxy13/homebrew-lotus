# Plugins for Lotus

Plugins add commands, tools for the AI and start screen lines to Lotus. How to build one: [PLUGINS.md](../PLUGINS.md).

## The examples here

| Plugin | Access | What it shows |
|---|---|---|
| [todo](todo/) | limited | A command (`lotus todo`), three AI tools (add, list, done) and a start screen line; its list lives in its data folder |
| [github](github/) | limited, with the internet | A plugin in Python: stars, forks and the newest release of a repository, and GitHub's zen on the start screen |
| [hello](hello/) | full | Lotus' own functions and settings – the look of `ui_*`, the theme, the features that are on |

Install one from a copy of this repository:

```
lotus plugin install path/to/homebrew-lotus/plugins/todo
```

## Plugins made by others

None yet – yours could be the first. Put your plugin in its own git repository (the `plugin.conf` at the top),
then open a pull request that adds a line here:

| Plugin | By | Access | What it does |
|---|---|---|---|
| | | | |

Lotus shows anyone who installs it what the plugin brings and may do. Plugins with full access run with the rights
of whoever installs them – say in your README why yours needs it.
