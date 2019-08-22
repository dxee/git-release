# git-release

## Installation
Copy `lib`,`git-changelog`,`git-release` to your local git repository, you must keep the structure the same.

## Usage
### Prepare config
Change `git-changelog/config.sh` to your own config value.

### Production release
eg:
```
./git-release/run-release.sh -r 1.0.29  -n 1.0.30
```
### Alpha release
eg:
```
./git-release/run-release.sh -r 1.0.29.alpha1  -n 1.0.29.alpha2
```
### No change log
```
./git-release/run-release.sh --nochglog -r 1.0.29.alpha1  -n 1.0.29.alpha2
```

### Hotfix 
- Start
```
./git-release/run-hotfix-start.sh 1.0.30
```
- Release
```
./git-release/run-hotfix-release.sh -r 1.0.30  -n 1.0.31
```