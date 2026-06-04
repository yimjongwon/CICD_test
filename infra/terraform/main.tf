# 상태 관리
terraform {
    required_version = ">= 1.14.0" # github action 에서 에러나지 않게 일부 수정
    required_providers {
      aws = {
            source  = "hashicorp/aws"
            version = "~> 6.0" 
      }
    }
    # terraform 상태 관리를 위한 remote 백엔드 설정
    backend "s3" {
        # 비워둔 값은 외부 파일(backend.hcl)에서 채우기
        # bucket            = ""                                # 미리 생성한 s3 버킷의 이름
        key                 = "lock-and-lock/terraform.tfstate" # /lock-and-lock/하위에 만들어 지도록
        region              = "ap-northeast-2"
        # dynamodb_table    = ""                                # 미리 준비된 dynamodb 테이블의 이름을 명시하면 lock 상태가 자동으로 관리된다.
        encrypt             = true                              # tfstate에는 민감한 정보가 있을 수 있기 때문에 암호화
    }
}







