# Personal Site Makefile
# Provides selective publishing options for org-mode content

.PHONY: all clean help homepage mfo sblp2024 assets quick incremental

# Default target
all: homepage

# Help target
help:
	@echo "Available targets:"
	@echo "  all         - Build everything (default)"
	@echo "  homepage    - Build main homepage only"
	@echo "  mfo         - Build MFO lectures only"
	@echo "  sblp2024    - Build SBLP2024 content only"
	@echo "  assets      - Copy assets only"
	@echo "  quick       - Build only recently changed files"
	@echo "  incremental - Enable incremental builds (faster)"
	@echo "  clean       - Remove generated files"

# Full build (current behavior)
homepage:
	emacs --batch --script make.el

# Build only MFO lectures
mfo: make-mfo.el
	emacs --batch --script make-mfo.el

# Build only SBLP2024 content
sblp2024: make-sblp2024.el
	emacs --batch --script make-sblp2024.el

# Copy assets only
assets: make-assets.el
	emacs --batch --script make-assets.el

# Quick build - only files changed in last 7 days
quick: make-quick.el
	emacs --batch --script make-quick.el

# Incremental build with timestamp checking
incremental: make-incremental.el
	emacs --batch --script make-incremental.el

# Clean generated files
clean:
	rm -rf docs/
	rm -f make-*.el

# Generate specialized make files
make-mfo.el: make.el
	@echo "Creating MFO-only build script..."
	@sed 's/("homepage" :components ("lectures-mfo" "homepage-mfo" "homepage-pages" "homepage-assets"))/("homepage" :components ("lectures-mfo" "homepage-mfo"))/' make.el > make-mfo.el

make-sblp2024.el: make.el
	@echo "Creating SBLP2024-only build script..."
	@sed 's/("homepage" :components ("lectures-mfo" "homepage-mfo" "homepage-pages" "homepage-assets"))/("homepage" :components ("homepage-pages"))/' make.el > make-sblp2024.el

make-assets.el: make.el
	@echo "Creating assets-only build script..."
	@sed 's/("homepage" :components ("lectures-mfo" "homepage-mfo" "homepage-pages" "homepage-assets"))/("homepage" :components ("homepage-assets"))/' make.el > make-assets.el

make-quick.el: make.el
	@echo "Creating quick build script..."
	@cp make.el make-quick.el
	@echo "" >> make-quick.el
	@echo ";; Only publish files modified in last 7 days" >> make-quick.el
	@echo "(setq org-publish-use-timestamps-flag t)" >> make-quick.el

make-incremental.el: make.el
	@echo "Creating incremental build script..."
	@sed 's/;; (org-publish-remove-all-timestamps)/(setq org-publish-use-timestamps-flag t)/' make.el > make-incremental.el
	@echo ";; Enable timestamp-based incremental builds" >> make-incremental.el

# File watching for development
watch:
	@echo "Watching for changes... (Press Ctrl+C to stop)"
	@while true; do \
		inotifywait -r -e modify,create,delete --include='\.org$$' . 2>/dev/null && \
		echo "Change detected, running incremental build..." && \
		make incremental; \
	done

# Check what would be rebuilt
check:
	@echo "Files that would be rebuilt:"
	@find . -name "*.org" -newer docs/index.html 2>/dev/null || echo "No timestamp comparison available"