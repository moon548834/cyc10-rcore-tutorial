rm -rf docs
gitbook build
mv _book docs
cd docs
rm update_book.sh
rm .gitignore
sudo git add .
git commit -m "update web"
cd ..
sudo git add .
git commit -m "update doc"
git push
