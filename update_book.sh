rm -rf docs
gitbook build
mv _book docs
cd docs
git add .
git commit -m "update web"
cd ..
git add .
git commit -m "$*"
git push
