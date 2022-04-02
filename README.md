# 手抜きmicro

はソースファイル1つのみのCSA将棋エンジンです。  
D言語で実装しています。  
駒得のみの評価です。

- ソース：micro.d


## 開発環境

- Debian 11


## ビルドのしかた

```
$ sudo apt install build-essential dub llvm-dev
$ make release
```


## 実行のしかた

```
$ ./micro <hostname> <username> <password>
```
