# Set this to the root of your project when deployed:
http_path = "/"
css_dir = "htdocs/stc/css"
sass_dir = "htdocs/scss"
images_dir = "htdocs/img"
javascripts_dir = "htdocs/js"

# on prod, run this to override:
#     compass compile -e production
#
# for development mode, with more verbose output (default):
#     compass compile
# or
#     compass compile -e development

env_from_cli = environment
if (environment.nil?)
  environment = :development
else
  environment = env_from_cli
end

# You can select your preferred output style here (can be overridden via the command line):
# output_style = :expanded or :nested or :compact or :compressed
output_style = (environment == :production) ? :compressed : :expanded

# To enable relative paths to assets via compass helper functions. Uncomment:
# relative_assets = true

# To disable debugging comments that display the original location of your selectors. Uncomment:
line_comments = (environment == :production) ? false : true

