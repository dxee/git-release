# git-release

## Usage
### Production release
eg:
```
./scripts/git-release/run-release.sh -r 1.0.29  -n 1.0.30
```
### Alpha release
eg:
```
./scripts/git-release/run-release.sh -r 1.0.29.alpha1  -n 1.0.29.alpha2
```
### No change log
```
./scripts/git-release/run-release.sh --nochglog -r 1.0.29.alpha1  -n 1.0.29.alpha2
```

### Hotfix 
- Start
```
./scripts/git-release/run-hotfix-start.sh 1.0.30
```
- Release
```
./scripts/git-release/run-hotfix-release.sh -r 1.0.30  -n 1.0.31
```