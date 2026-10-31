# The commands, in order

Nothing below has been run for the video. Copy the real install lines from the release notes or `data/project.tsv`
(the website shows them) when recording, so that the video shows exactly what a viewer would type.

```
# 4 – Mac
curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh

# 5 – Linux
curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | sh

# 3
lotus
/clock
/weather Amsterdam

# 6
lotus doctor

# 7
/ai
/permissions

# 8
/img convert ~/Pictures/trip --to webp --max 1920

# 9
/pets
/zetamac

# 10
/plugin install plugins/todo
/todo add milk
/todo

# 11 (a Mac with Docker, in the repository)
LOTUS_TEST_PRIV=1 tests/docker/par.sh ubuntu
LOTUS_TEST_PRIV=1 tests/docker/par.sh debian
```

Before each scene run `clear` and, where a scene shows the start screen, type `lotus`.
