from app.models.models import (
    Base, User, Department, File, Permission, AuditLog,
    CopyTemplate, CopyHistory,
    # 3.1
    Customer, CustomerBehavior, CustomerSatisfaction,
    ChurnConfig, ChurnWarning, MarketingProposal,
    # 3.2
    MarketingProject, ProjectBrief, CommunityInteraction,
    CommunityDailyStat, KnowledgeEntry, QAChatRecord,
    # 3.3
    ContractTemplate, Contract, ContractVersion,
    BiddingKnowledgeDir, BiddingKnowledgeDoc,
    BiddingProcess, Supplier, Instructor,
    # Phase 4: PM
    PmProject, VisitLog, Courseware, ProjectReport,
    # Phase 4: HR
    Employee, Resume, Approval,
    # Phase 4: Finance
    Settlement, Expense, Voucher,
)

__all__ = [
    "Base", "User", "Department", "File", "Permission", "AuditLog",
    "CopyTemplate", "CopyHistory",
    "Customer", "CustomerBehavior", "CustomerSatisfaction",
    "ChurnConfig", "ChurnWarning", "MarketingProposal",
    "MarketingProject", "ProjectBrief", "CommunityInteraction",
    "CommunityDailyStat", "KnowledgeEntry", "QAChatRecord",
    "ContractTemplate", "Contract", "ContractVersion",
    "BiddingKnowledgeDir", "BiddingKnowledgeDoc",
    "BiddingProcess", "Supplier", "Instructor",
    "PmProject", "VisitLog", "Courseware", "ProjectReport",
    "Employee", "Resume", "Approval",
    "Settlement", "Expense", "Voucher",
]
