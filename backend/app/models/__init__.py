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
]
