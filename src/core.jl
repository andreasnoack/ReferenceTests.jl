#################################################
# Rendering
# This controls how failures are displayed
abstract type RenderMode end
struct Diff <: RenderMode end

abstract type BeforeAfter <: RenderMode end
struct BeforeAfterLimited <: BeforeAfter end
struct BeforeAfterFull <: BeforeAfter end
struct BeforeAfterImage <: BeforeAfter end

render_item(::RenderMode, item) = println(item)
function render_item(::BeforeAfterLimited, item)
    show(IOContext(stdout, :limit=>true, :displaysize=>(20,80)), "text/plain", item)
    println()
end
function render_item(::BeforeAfterImage, item)
    str_item = @withcolor ImageInTerminal.encodeimg(ImageInTerminal.SmallBlocks(), ImageInTerminal.TermColor256(), item, 20, 40)[1]
    println("eltype: ", eltype(item))
    println("size: ", map(length, axes(item)))
    println("thumbnail:")
    println.(str_item)
end

## 2 arg form render for comparing
function render(mode::BeforeAfter, reference, actual)
    println("- REFERENCE -------------------")
    render_item(mode, reference)
    println("-------------------------------")
    println("- ACTUAL ----------------------")
    render_item(mode, actual)
    println("-------------------------------")
end
function render(::Diff, reference, actual)
    println("- DIFF ------------------------")
    @withcolor println(deepdiff(reference, actual))
    println("-------------------------------")
end

## 1 arg form render for new content
function render(mode::RenderMode, actual)
    println("- NEW CONTENT -----------------")
    render_item(mode, actual)
    println("-------------------------------")
end

#######################################
# IO
# Right now this basically just extends FileIO to support some things as text files

const TextFile = Union{File{format"TXT"}, File{format"SHA256"}}

function loadfile(T, file::File)
    T(load(file)) # Fallback to FileIO
end

function loadfile(T, file::TextFile)
    read(file.filename,String)
end

function savefile(file::File, content)
    save(file, content) # Fallback to FileIO
end

function savefile(file::TextFile, content)
    write(file.filename, content)
end

##########################################

# Final function
# all other functions should hit one of this eventually
# Which handles the actual testing and user prompting

function _test_reference(rendermode, file::File, actual)
    _test_reference(isequal, rendermode, file, actual)
end

function _test_reference(equiv, rendermode, file::File, actual::T) where T
    path = file.filename
    dir, filename = splitdir(path)
    try
        reference = loadfile(T, file)
        if equiv(reference, actual)
            @test true # to increase test counter if reached
        else # test failed
            println("Test for \"$filename\" failed.")
            render(rendermode, reference, actual)
            if isinteractive()
                if input_bool("Replace reference with actual result (path: $path)?")
                    savefile(file, actual)
                    @warn("Please run the tests again for any changes to take effect")
                else
                    @test false
                end
            else
                error("You need to run the tests interactively with 'include(\"test/runtests.jl\")' to update reference images")
            end
        end
    catch ex
        if ex isa SystemError || # File doesn't exist
            (Sys.isapple() && ex isa MethodError) ||  # MethodError is for OSX for some reason
            (ex isa ErrorException && startswith(ex.msg, "unable to open"))

            println("Reference file for \"$filename\" does not exist.")
            render(rendermode, actual)
            if isinteractive()
                if input_bool("Create reference file with above content (path: $path)?")
                    mkpath(dir)
                    savefile(file, actual)
                    @warn("Please run the tests again for any changes to take effect")
                else
                    @test false
                end
            else
                error("You need to run the tests interactively with 'include(\"test/runtests.jl\")' to create new reference images")
            end
        else
            rethrow(ex)
        end
    end
end
