# Copyright 2019 Alexandre Terrasa <alexandre@moz-code.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module github2

import base64
import curl
import json

class API

	# Github API OAuth token
	#
	# To access your private ressources, you must
	# [authenticate](https://developer.github.com/guides/basics-of-authentication/).
	#
	# For client applications, Github recommands to use the
	# [OAuth tokens](https://developer.github.com/v3/oauth/) authentification method.
	#
	#
	#
	# Be aware that there is [rate limits](https://developer.github.com/v3/rate_limit/)
	# associated to the key.
	var auth: nullable String = null is optional

	# User agent (is used by github to contact devs in case of problems)
	# Eg. "Awesome-Octocat-App"
	var user_agent: nullable String = "nit_github_api" is optional

	# Headers to use on all requests
	var headers: HeaderMap is lazy do
		var map = new HeaderMap
		var auth = self.auth
		if auth != null then
			map["Authorization"] = "token {auth}"
		end
		var user_agent = self.user_agent
		if user_agent != null then
			map["User-Agent"] = user_agent
		end
		# FIXME remove when projects and team are no more in beta
		map["Accept"] = "application/vnd.github.inertia-preview+json"
		map["Accept"] = "application/vnd.github.hellcat-preview+json"
		return map
	end

	# Github API base url.
	#
	# Default is `https://api.github.com` and should not be changed.
	var api_url = "https://api.github.com"

	var last_error: nullable GithubError = null

	private fun send(method, path: String, body: nullable String): nullable Serializable do
		last_error = null
		path = sanitize_uri(path)
		var uri = "{api_url}{path}"
		var request = new CurlHTTPRequest(uri)
		request.method = method
		request.user_agent = user_agent
		request.headers = headers
		request.body = body
		return check_response(uri, request.execute)
	end

	fun get(path: String): nullable Object do
		return deserialize(send("GET", path))
	end

	fun post(path: String, data: nullable String): nullable Object do
		return deserialize(send("POST", path, data))
	end

	fun put(path: String, data: nullable String): nullable Object do
		return deserialize(send("PUT", path, data))
	end

	fun delete(path: String): nullable Object do
		return deserialize(send("DELETE", path))
	end

	# Escape `uri` in an acceptable format for Github.
	private fun sanitize_uri(uri: String): String do
		# TODO better URI escape.
		return uri.replace(" ", "%20")
	end

	private fun check_response(uri: String, response: CurlResponse): nullable Serializable do
		if response isa CurlResponseSuccess then
			return response.body_str
		else if response isa CurlResponseFailed then
			last_error = new GithubAPIError(
				"Request to Github API failed",
				response.error_msg,
				response.error_code,
				uri
			)
			return null
		end
		abort
	end

	# Deserialize an object
	private fun deserialize(string: nullable Serializable): nullable Object do
		if string == null then return null
		# print string
		var deserializer = new GithubDeserializer(string.to_s)
		var res = deserializer.deserialize
		if deserializer.errors.not_empty then
			last_error = new GithubDeserializerErrors("Deserialization failed", deserializer.errors)
			return null
		else if res isa GithubError then
			last_error = res
			return null
		end
		return res
	end

	fun get_user(login: String): nullable User do
		return get("/users/{login}").as(nullable User)
	end

	fun get_org(login: String): nullable Org do
		return get("/orgs/{login}").as(nullable Org)
	end

	fun get_team(org_login, team_name: String): nullable Team do
		return get("/orgs/{org_login}/teams/{team_name}").as(nullable Team)
	end

	fun post_team(org_login: String, team: Team): nullable Team do
		return post("/orgs/{org_login}/teams", team.post_data).as(nullable Team)
	end

	fun get_repo(repo_slug: String): nullable Repo do
		return get("/repos/{repo_slug}").as(nullable Repo)
	end

	fun post_repo(repo: PostRepo): nullable Repo do
		return post("/user/repos", repo.post_data).as(nullable Repo)
	end

	fun get_repo_labels(repo_slug: String): nullable Array[Label] do
		var arr = get("/repos/{repo_slug}/labels")
		var res = new Array[Label]
		if not arr isa Array[Object] then return res
		for obj in arr do
			if obj isa Label then res.add obj
		end
		return res
	end

	fun post_repo_org(org_login: String, repo: PostRepo): nullable Repo do
		return post("/orgs/{org_login}/repos", repo.post_data).as(nullable Repo)
	end

	fun get_project(id: Int): nullable Project do
		return get("/projects/{id}").as(nullable Project)
	end

	fun post_project_org(org_login: String, project: Project): nullable Project do
		return post("/orgs/{org_login}/projects", project.post_data).as(nullable Project)
	end

	fun get_issue(repo_slug: String, id: Int): nullable Issue do
		return get("/repos/{repo_slug}/issues/{id}").as(nullable Issue)
	end

	fun post_issue(repo_slug: String, issue: PostIssue): nullable Issue do
		return post("/repos/{repo_slug}/issues", issue.post_data).as(nullable Issue)
	end

	fun get_label(repo_slug: String, label_name: String): nullable Label do
		return get("/repos/{repo_slug}/labels/{label_name}").as(nullable Label)
	end

	fun post_label(repo_slug: String, lbl: Label): nullable Label do
		return post("/repos/{repo_slug}/labels", lbl.post_data).as(nullable Label)
	end

	fun delete_label(repo_slug: String, label_name: String): nullable Label do
		return delete("/repos/{repo_slug}/labels/{label_name}").as(nullable Label)
	end

	fun get_milestone(repo_slug: String, milestone_number: Int): nullable Milestone do
		return get("/repos/{repo_slug}/milestones/{milestone_number}").as(nullable Milestone)
	end

	fun post_milestone(repo_slug: String, milestone: Milestone): nullable Milestone do
		return post("/repos/{repo_slug}/milestones", milestone.post_data).as(nullable Milestone)
	end

	fun get_readme(repo_slug: String): nullable File do
		return get("/repos/{repo_slug}/readme").as(nullable File)
	end

	fun get_file(repo_slug: String, path: String): nullable File do
		return get("/repos/{repo_slug}/contents/{path}").as(nullable File)
	end

	fun put_file(repo_slug: String, path: String, file: FilePost): nullable File do
		return put("/repos/{repo_slug}/contents/{path}", file.post_data).as(nullable File)
	end
end

class GithubSerializer
	super JsonSerializer

	redef fun serialize_attribute(name, value) do
		if value == null then return
		super
	end
end

# JsonDeserializer specific for Github objects.
class GithubDeserializer
	super JsonDeserializer

	redef fun class_name_heuristic(obj) do
		if obj.has_key("resource") and obj.has_key("code") then
			return "GithubFieldError"
		else if obj.has_key("message") and obj.has_key("documentation_url") then
			if obj.has_key("errors") then return "GithubValidationError"
			return "GithubError"
		else if obj.has_key("type") then
			if obj["type"] == "file" then return "File"
			if obj["type"] == "User" then return "User"
			if obj["type"] == "Organization" then return "Org"
		else if obj.has_key("full_name") then
			return "Repo"
		else if obj.has_key("members_count") then
			return "Team"
		else if obj.has_key("columns_url") then
			return "Project"
		else if obj.has_key("due_on") then
			return "Milestone"
		else if obj.has_key("number") and obj.has_key("title") then
			return "Issue"
		else if obj.has_key("color") then
			return "Label"
		else if obj.has_key("due_date") then
			return "Milestone"
		end
		return null
	end

	redef fun deserialize_class(class_name) do
		if class_name == "File" then
			var encoding = deserialize_attribute("encoding").as(nullable String)
			var size = deserialize_attribute("size").as(nullable Int)
			var name = deserialize_attribute("name").as(nullable String)
			var path = deserialize_attribute("path").as(nullable String)
			var content = deserialize_attribute("content").as(nullable String)
			if content != null then content = content.decode_base64.to_s
			var sha = deserialize_attribute("sha").as(nullable String)
			return new File(encoding, size, name, path, content, sha)
		end
		return super
	end
end

# Something returned by the Github API.
#
# Mainly a Nit wrapper around a JSON objet.
abstract class GithubObject
	super Serializable

	fun post_data: String do
		var stream = new StringWriter
		var serializer = new GithubSerializer(stream)
		serializer.plain_json = true
		serializer.pretty_json = false
		serializer.serialize self
		stream.close
		return stream.to_s
	end
end

class GithubError
	super Error
	serialize

	fun body: String do return ""
end

class GithubAPIError
	super GithubError

	var response: String
	var status_code: Int
	var requested_uri: String

	redef fun body do
		var b = new Buffer
		b.append "Code: {status_code}\n"
		b.append "Response: {response}\n"
		b.append "Requested URI: {requested_uri}\n"
		return b.write_to_string
	end
end

class GithubValidationError
	super GithubError

	var errors: nullable Array[nullable Serializable] = null is optional

	redef fun body do return "{(errors or else new Array[String]).join("\n")}"
end

class GithubFieldError
	super GithubError

	var resource: String
	var code: String

	redef fun to_s do return "{super}: {code}"
end

class GithubDeserializerErrors
	super GithubError

	var deserizalization_errors: Array[Error]

	redef fun body do return "{deserizalization_errors.join(", ")}"
end

class GitUser
	super GithubObject
	serialize

	var name: nullable String is writable
	var email: nullable String is writable
end

class User
	super GitUser
	serialize

	# Github login.
	var login: String is writable

	var id: Int

	# Avatar image url for this user.
	var avatar_url: nullable String is writable

	# User public blog if any.
	var blog: nullable String is writable
end

class Org
	super User
	serialize
end

class Team
	super GithubObject
	serialize

	var name: String
	var description: nullable String = null is optional, writable
	var maintainers: nullable Array[String] = null is optional, writable
	var repo_names: nullable Array[String] = null is optional, writable
	var privacy: nullable String = null is optional, writable
	var permission: nullable String = null is optional, writable
	var parent_team_id: nullable Int = null is optional, writable
	var id: nullable Int = null is optional, writable
end

class Repo
	super GithubObject
	serialize

	var full_name: String is writable

	# Repo short name on Github.
	var name: String is writable

	# Get the repo owner.
	var owner: User is writable

	# Repo default branch name.
	var default_branch: String is writable
end

class PostRepo
	super GithubObject
	serialize

	var name: String
	var description: nullable String = null is optional, writable
	var homepage: nullable String = null is optional, writable
	var is_private: nullable Bool = null is optional, serialize_as("private"), writable
	var has_issues: nullable Bool = null is optional, writable
	var has_projects: nullable Bool = null is optional, writable
	var has_wiki: nullable Bool = null is optional, writable
	var team_id: nullable Int = null is optional, writable
	var auto_init: nullable Bool = null is optional, writable
	var gitignore_template: nullable String = null is optional, writable
	var license_template: nullable String = null is optional, writable
	var allow_squash_merge: nullable Bool = null is optional, writable
	var allow_merge_commit: nullable Bool = null is optional, writable
	var allow_rebase_merge: nullable Bool = null is optional, writable
end

class Project
	super GithubObject
	serialize

	var name: String
	var body: nullable String = null is optional

	var id: nullable Int = null is optional
	var number: nullable Int = null is optional
	var state: nullable String = null is optional
end

class Issue
	super GithubObject
	serialize

	var id: Int
	var number: Int
	var state: String
	var title: String
	var body: nullable String = null is optional
	var user: nullable User = null is optional
	var labels: nullable Array[Label] = null is optional
	var assignee: nullable User = null is optional
	var assignees: nullable Array[User] = null is optional
	# TODO milestone
	# var milestone: nullable Int = null is optional
end

class PostIssue
	super GithubObject
	serialize

	var title: String
	var body: nullable String = null is optional
	var assignee: nullable String = null is optional
	var milestone: nullable Int = null is optional
	var labels: nullable Array[String] = null is optional
	var assignees: nullable Array[String] = null is optional
end

class Label
	super GithubObject
	serialize

	var name: String
	var color: String
	var description: nullable String = null is optional
	var default: nullable Bool = null is optional
end

class Milestone
	super GithubObject
	serialize

	var title: String
	var state: nullable String = null is optional
	var description: nullable String = null is optional
	var creator: nullable User = null is optional
	var due_date: nullable String = null is optional
end

class File
	super GithubObject
	serialize

	var encoding: nullable String = null is optional
	var size: nullable Int = null is optional
	var name: nullable String = null is optional
	var path: nullable String = null is optional
	var content: nullable String = null is optional
	var sha: nullable String = null is optional
end

class FilePost
	super GithubObject
	serialize

	var message: String
	var content: String
	var branch: nullable String = null is optional
	var committer: nullable GitUser = null is optional
	var author: nullable GitUser = null is optional

	redef fun core_serialize_to(serializer) do
		serializer.serialize_attribute("message", message)
		serializer.serialize_attribute("content", (content).encode_base64)
		serializer.serialize_attribute("branch", branch)
		serializer.serialize_attribute("committer", committer)
		serializer.serialize_attribute("author", author)
	end
end

var token_file = "token"
var path = token_file.to_path
assert path.exists
var token = path.read_all.trim

var api = new API(token, "prez")

# print api.get_user("Morriar") or else "NULL"
# print api.get_user("Morriarisdasd") or else "NULL"
# print api.get_repo("Morriar/nit") or else "NULL"
# print api.get_org("moz-code") or else "NULL"
# print api.get_team("moz-code", "test1") or else "NULL"
# print api.get_project(2643689) or else "NULL"
# print api.get_issue("moz-code/test1", 1) or else "NULL"
# print api.get_issue("moz-code/test1", 1).as(not null).labels or else "NULL"
# print api.get_label("moz-code/test1", "bug") or else "NULL"
# print api.get_milestone("moz-code/test1", 1) or else "NULL"
# print api.get_readme("moz-code/test1") or else "NULL"
# print api.get_file("moz-code/test1", "README.md") or else "NULL"

# var team = new Team(name = "test3")
# print api.post_team("moz-code", team) or else "NULL"

# var repo = new PostRepo(name = "test1")
# print api.post_repo_org("moz-code", repo) or else "NULL"

# var project = new Project("test2")
# print api.post_project_org("moz-code", project) or else "NULL"

# var issue = new PostIssue("title 1", "body", "Morriar", labels = ["bug", "question"])
# print api.post_issue("moz-code/test1", issue) or else "NULL"

# var lbl = new Label("Test1", "000000")
# print api.post_label("moz-code/test1", lbl) or else "NULL"

# var milestone = new Milestone("Test1", "open")
# print api.post_milestone("moz-code/test1", milestone) or else "NULL"

# var file = new FilePost("test", "CONTENT", "master", new GitUser("Morriar", "alexandre@moz-code.org"))
# api.put_file("moz-code/test1", "README.md", file)

var error = api.last_error
if error != null then
	print error
end
