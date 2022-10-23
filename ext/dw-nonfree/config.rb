# Set this to the root of your project when deployed:
http_path = "/"
css_dir = "htdocs/stc/css"
sass_dir = "htdocs/scss"
images_dir = "htdocs/img"
javascripts_dir = "htdocs/js"

add_import_path "../../htdocs/scss"

env_from_cli = environment
if (environment.nil?)
  environment = :development
else
  environment = env_from_cli
end

output_style  = (environment == :production) ? :compressed : :expanded
line_comments = (environment == :production) ? false : true

