pipelineJob('hello-from-jenkinsfile') {
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/ibugithub/tryKube.git')
                    }
                    branches('main')
                }
                scriptPath('jenkins-demo/Jenkinsfile')
            }
        }
    }
}
